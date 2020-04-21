package ambassadorinstallation

import (
	"fmt"
	"os"
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

// fileExists checks if a file exists and is not a directory before we
// try using it to prevent further errors.
func fileExists(filename string) bool {
	info, err := os.Stat(filename)
	if os.IsNotExist(err) {
		return false
	}
	return !info.IsDir()
}
