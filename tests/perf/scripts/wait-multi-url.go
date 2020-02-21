//
// wait-multi-url: a simple script in Go for waiting for URLs
//
// It can be used for waiting for all the URLs in a pattern. For example:
//
// - the pattern can be specified like `https://172.19.0.3/echo-@/` (where `@` will be replaced by the "index")
// - `--start` and `--end` are used for specifying the "index" range
// - `--wait-code` is used for waiting for a specific HTTP return code
// - `--wait-error` is used for waiting for any error
//
package main

// NOTE(alvaro): do not import any vendors, so we can just `go run` this script...
import (
	"context"
	"crypto/tls"
	"flag"
	"fmt"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	// default character to be replaced by the index
	defReplaceVar = "@"

	// default timeout for checking all the URLs provided
	defTimeout = 5 * time.Minute

	// default interval for retries
	defRetryInterval = 1 * time.Second

	// timeout for receiving the header
	defResponseHeaderTimeout = 1 * time.Second

	// print interval
	defPrintInterval = 30 * time.Second
)

type config struct {
	startRange  int
	endRange    int
	url         string
	reason      string
	timeout     time.Duration
	concurrency int

	waitCode  int
	waitError bool

	verbose bool
}

func main() {
	cfg := config{}

	flag.IntVar(&cfg.startRange, "start", 1, "start of index")
	flag.IntVar(&cfg.endRange, "end", 1000, "end of index")
	flag.StringVar(&cfg.url, "url", "",
		fmt.Sprintf("urls pattern (replacing %s by the index) (ie, 'http://something/echo-%s')",
			defReplaceVar, defReplaceVar))
	flag.IntVar(&cfg.waitCode, "wait-code", 200, "accept only this HTTP code")
	flag.BoolVar(&cfg.waitError, "wait-error", false, "wait for any error: connection refused, 503, 404, etc")
	flag.DurationVar(&cfg.timeout, "timeout", defTimeout, "timeout for checking all the URLs (in seconds)")
	flag.BoolVar(&cfg.verbose, "verbose", false, "verbose output")
	flag.StringVar(&cfg.reason, "reason", "", "message to print with the time")
	flag.IntVar(&cfg.concurrency, "concurrency", 50, "the number of goroutines that are allowed to run concurrently")
	flag.Parse()

	if cfg.url == "" {
		fmt.Printf("no URL provided with --url\n")
		os.Exit(1)
	}
	ctx, _ := context.WithTimeout(context.Background(), cfg.timeout)

	if cfg.waitError {
		cfg.waitCode = 0
	}

	waitWhat := ""
	if cfg.waitCode != 0 {
		waitWhat = fmt.Sprintf("code %d", cfg.waitCode)
	} else if cfg.waitError {
		waitWhat = "an error"
	}

	startTime := time.Now()
	if strings.Contains(cfg.url, defReplaceVar) {
		fmt.Printf("[%s] Waiting for all %s (%d URLs) to return %s (for up to %s, concurrency %d)\n",
			time.Now(), cfg.url, cfg.endRange-cfg.startRange, waitWhat, cfg.timeout, cfg.concurrency)

		concurrentGoroutines := make(chan struct{}, cfg.concurrency)
		var wg sync.WaitGroup
		for i := cfg.startRange; i <= cfg.endRange; i++ {
			thisURL := strings.ReplaceAll(cfg.url, defReplaceVar, strconv.Itoa(i))

			wg.Add(1)
			go func(ctx context.Context, url string) {
				defer func() { wg.Done() }()

				concurrentGoroutines <- struct{}{} // insert in the concurrency channel: will block if full
				keepCheckingURL(ctx, url, cfg)
				<-concurrentGoroutines // take out of the concurrency channel
			}(ctx, thisURL)
		}
		wg.Wait()

	} else {
		fmt.Printf("[%s] Waiting for single URL %s to return %s (for up to %s)\n",
			time.Now(), cfg.url, waitWhat, cfg.timeout)
		keepCheckingURL(ctx, cfg.url, cfg)
	}

	elapsed := time.Since(startTime)
	if cfg.reason != "" {
		fmt.Printf("[%s] Elapsed time: %s: %s\n", time.Now(), cfg.reason, elapsed)
	} else {
		fmt.Printf("[%s] Elapsed time: %s\n", time.Now(), elapsed)
	}

	timeLimit, _ := ctx.Deadline()
	if time.Now().After(timeLimit) {
		os.Exit(1)
	}
}

// keepCheckingURL keeps checking an URL until it returns the expected code
func keepCheckingURL(ctx context.Context, url string, cfg config) {
	checkURL := func(u string) (resp *http.Response, err error) {
		// we create a new client with every check: otherwise it keeps connections
		// and it leads to some problems....
		client := &http.Client{
			Transport: &http.Transport{
				MaxIdleConns:          50,
				ResponseHeaderTimeout: defResponseHeaderTimeout,
				TLSHandshakeTimeout:   defResponseHeaderTimeout,
				DialContext: (&net.Dialer{
					Timeout: defResponseHeaderTimeout,
				}).DialContext,
				IdleConnTimeout:    30 * time.Second,
				DisableCompression: true,
				TLSClientConfig: &tls.Config{
					InsecureSkipVerify: true,
				},
			},
			Timeout: defResponseHeaderTimeout,
		}
		return client.Head(u)
	}

	printRespErr := func(what string, resp *http.Response, err error) bool {
		if resp != nil {
			fmt.Printf("[%s] %s: %s: code=%d\n", time.Now(), url, what, resp.StatusCode)
		} else if err != nil {
			fmt.Printf("[%s] %s: %s: %s\n", time.Now(), url, what, err.Error())
		} else {
			fmt.Printf("[%s] %s: %s\n", time.Now(), url, what)
		}
		return true
	}

	isWhatWeExpected := func(resp *http.Response, err error) bool {
		if err != nil && cfg.waitError {
			return printRespErr("condition met", resp, err)
		}
		if err == nil {
			if cfg.waitError {
				switch resp.StatusCode {
				case 404:
					return printRespErr("condition met", resp, err)
				case 503:
					return printRespErr("condition met", resp, err)
				}
			}
			if cfg.waitCode == resp.StatusCode {
				return printRespErr("condition met", resp, err)
			}
			if cfg.waitCode == 0 {
				return printRespErr("condition met", resp, err)
			}
		}
		if cfg.verbose {
			printRespErr("not what we are waiting for", resp, err)
		}
		return false
	}

	timeLimit, _ := ctx.Deadline()

	// perform an initial check
	if res, err := checkURL(url); isWhatWeExpected(res, err) {
		fmt.Printf("[%s] %s: OK\n", time.Now(), url)
		return
	}
	// it was not available: try in a loop until the timeout is reached...
	lastPrint := time.Now()
	for {
		select {
		case <-time.After(defRetryInterval):
			if res, err := checkURL(url); isWhatWeExpected(res, err) {
				fmt.Printf("[%s] %s: OK\n", time.Now(), url)
				return
			}
			if time.Since(lastPrint) > defPrintInterval {
				now := time.Now()
				fmt.Printf("[%s] %s: (condition not met yet. still trying: %s left...)\n",
					time.Now(), url, timeLimit.Sub(now))
				lastPrint = now
			}

		case <-ctx.Done():
			fmt.Printf("[%s] %s: TIMEOUT: %s\n", time.Now(), url, ctx.Err())
			return
		}
	}
}
