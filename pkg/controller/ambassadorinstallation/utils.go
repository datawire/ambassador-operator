package ambassadorinstallation

import (
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

func contains(l []string, s string) bool {
	for _, elem := range l {
		if elem == s {
			return true
		}
	}
	return false
}

// fileIsArchive returns True if the URL points to an archive
func fileIsArchive(u url.URL) bool {
	path := u.Path
	ext := filepath.Ext(path)

	switch ext {
	case ".tar.gz", ".gz", ".zip":
		return true
	default:
		return false
	}
}

// parse a repo and tag from an image name
// for example: "quay.io/datawire/aes:1.0" -> ("quay.io/datawire/aes", "1.0")
func parseRepoTag(s string) (string, string, error) {
	res := strings.Split(s, ":")
	if len(res) != 2 {
		return "", "", fmt.Errorf("could not parse image name %s", s)
	}
	return res[0], res[1], nil
}

func getEnvDuration(name string, d time.Duration) time.Duration {
	var err error
	updateInterval := d
	if e := os.Getenv(name); len(e) > 0 {
		updateInterval, err = time.ParseDuration(e)
		if err != nil {
			log.Error(err, "Could not parse update interval from environ variable: IGNORED", "value", e)
		}
	}
	return updateInterval
}

// DownloadFile will download a url to a local file. It's efficient because it will
// write as it downloads and not load the whole file into memory.
func downloadFile(filepath string, url string) error {
	resp, err := http.Get(url)
	if err != nil {
		return err
	}
	defer func() { _ = resp.Body.Close() }()

	// Create the file
	out, err := os.Create(filepath)
	if err != nil {
		return err
	}
	defer func() { _ = out.Close() }()

	// Write the body to file
	_, err = io.Copy(out, resp.Body)
	return err
}
