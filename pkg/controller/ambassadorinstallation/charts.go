package ambassadorinstallation

import (
	"encoding/hex"
	"errors"
	"fmt"
	"io/ioutil"
	"math/rand"
	"net/url"
	"os"
	"path/filepath"

	"github.com/mholt/archiver/v3"
	"github.com/operator-framework/operator-sdk/pkg/helm/release"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/helm/pkg/chartutil"
	"k8s.io/helm/pkg/getter"
	"k8s.io/helm/pkg/helm/environment"
	"k8s.io/helm/pkg/helm/helmpath"
	"k8s.io/helm/pkg/repo"
	"sigs.k8s.io/controller-runtime/pkg/manager"
)

const (
	// The default URL for getting the charts listing
	DefaultHelmRepoURL = "https://www.getambassador.io"

	// The default chart name
	DefaultChartName = "ambassador"
)

var (
	// ErrUnknownHelmRepoScheme is unknown helm repo scheme
	ErrUnknownHelmRepoScheme = errors.New("unknown helm repo scheme")

	// ErrNoChartDirFound is no chart directory found
	ErrNoChartDirFound = errors.New("no chart directory found")
)

// HelmManager is a remote Helm repo or a file, provided with an URL
type HelmManager struct {
	mgr     manager.Manager
	url     *url.URL
	cvr     ChartVersionRule
	values  map[string]string
	downDir string
}

// NewHelmManager creates a new charts manager
// The Helm Manager will use the URL provided, and download (lazily) a Chart that
// obeys the Version Rule.
func NewHelmManager(mgr manager.Manager, u string, cvr ChartVersionRule, values map[string]string) (HelmManager, error) {
	// process the URL, using the default URL when not provided
	if u == "" {
		u = DefaultHelmRepoURL
	}
	pu, err := url.Parse(u)
	if err != nil {
		return HelmManager{}, err
	}

	return HelmManager{
		mgr:    mgr,
		url:    pu,
		cvr:    cvr,
		values: values,
	}, nil
}

// GetValues returns the values associated with this Helm manager
func (lc HelmManager) GetValues() map[string]string {
	return lc.values
}

// GetValues returns the version rules associated with this Helm manager
func (lc HelmManager) GetVersionRule() ChartVersionRule {
	return lc.cvr
}

// Download performs the download of the Chart pointed by the URL, returning a directory with a Chart.yaml inside.
func (lc *HelmManager) GetManagerFor(o *unstructured.Unstructured) (release.Manager, error) {
	log := log.WithValues("URL", lc.url)

	// parse the helm repo URL and try to download the helm chart
	switch lc.url.Scheme {
	case "http", "https":
		if fileIsArchive(*lc.url) {
			log.V(1).Info("URL is an archive: downloading")
			if err := lc.downloadChartFile(lc.url); err != nil {
				return nil, err
			}
		} else {
			log.V(1).Info("URL is a Helm repo: looking for version in repo")
			u, err := lc.findInRepo()
			if err != nil {
				return nil, err
			}

			log.V(1).Info("Downloading release", "URL", u)
			if err := lc.downloadChartFile(u); err != nil {
				return nil, err
			}
		}

	default:
		return nil, fmt.Errorf("%w: u.Scheme", ErrUnknownHelmRepoScheme)
	}

	log.V(1).Info("Finding chart")
	chartDir, err := lc.findChartDir()
	if err != nil {
		return nil, err
	}

	factory := release.NewManagerFactory(lc.mgr, chartDir)
	chartMgr, err := factory.NewManager(o, lc.values)
	if err != nil {
		return nil, err
	}

	return chartMgr, nil
}

// Cleanup removed all the download directories
func (lc *HelmManager) Cleanup() error {
	if lc.downDir != "" {
		log.V(1).Info("Removing downloads directory", "directory", lc.downDir)
		_ = os.RemoveAll(lc.downDir)
		lc.downDir = ""
	}
	return nil
}

// downloadChartFile downloads a Chart archive from a URL
func (lc *HelmManager) downloadChartFile(url *url.URL) error {
	// creates/erases the downloads directory, ignoring any error (just in case it does not exist)
	d, err := ioutil.TempDir("", "chart-download")
	if err != nil {
		return err
	}
	lc.downDir = d

	filename := filepath.Base(url.Path)

	log := log.WithValues("URL", url)
	// generates a random filename in /tmp (but it does not create the file)
	randBytes := make([]byte, 16)
	rand.Read(randBytes)
	tempFilename := filepath.Join(os.TempDir(), fmt.Sprintf("%s-%s", hex.EncodeToString(randBytes), filename))

	log = log.WithValues("filename", tempFilename, "dest", lc.downDir)
	log.V(1).Info("Downloading file")
	if err := downloadFile(tempFilename, url.String()); err != nil {
		return err
	}
	defer func() { _ = os.Remove(tempFilename) }()

	log.V(1).Info("Uncompressing file")
	if err := archiver.Unarchive(tempFilename, lc.downDir); err != nil {
		return err
	}
	log.V(1).Info("File uncompressed")

	return nil
}

func (lc *HelmManager) findInRepo() (*url.URL, error) {
	chartName := DefaultChartName
	repoURL := lc.url.String()

	// Download and write the index file to a temporary location
	tempIndexFile, err := ioutil.TempFile("", "tmp-repo-file")
	if err != nil {
		return nil, fmt.Errorf("cannot write index file for repository requested")
	}
	defer func() { _ = os.Remove(tempIndexFile.Name()) }()

	home := helmpath.Home(environment.DefaultHelmHome)
	settings := environment.EnvSettings{
		Home: home,
	}

	c := repo.Entry{
		URL: repoURL,
	}
	r, err := repo.NewChartRepository(&c, getter.All(settings))
	if err != nil {
		return nil, err
	}
	if err := r.DownloadIndexFile(tempIndexFile.Name()); err != nil {
		return nil, fmt.Errorf("looks like %q is not a valid chart repository or cannot be reached: %s", repoURL, err)
	}

	// Read the index file for the repository to get chart information and return chart URL
	repoIndex, err := repo.LoadIndexFile(tempIndexFile.Name())
	if err != nil {
		return nil, err
	}

	versions, ok := repoIndex.Entries[chartName]
	if !ok {
		return nil, repo.ErrNoChartName
	}
	if len(versions) == 0 {
		return nil, repo.ErrNoChartVersion
	}

	parsedURL := func(u string) (*url.URL, error) {
		absoluteChartURL, err := repo.ResolveReferenceURL(repoURL, u)
		if err != nil {
			return nil, fmt.Errorf("failed to make chart URL absolute: %v", err)
		}

		log.V(1).Info("Chart URL", "URL", absoluteChartURL)
		pu, err := url.Parse(absoluteChartURL)
		if err != nil {
			return nil, err
		}
		return pu, nil
	}

	//
	// note: when looking for the right chart, there are two versions to consider:
	//
	// - the AppVersion is the version of the software **installed by** the Chart (ie, Ambassador 1.0)
	// - the Version is the version of the Chart (ie, Ambassador Chart 0.6)
	//
	// So there can be multiple Chart Versions for the same `AppVersion`. For example, we updated
	// the Helm Chart several times for AppVersion=1.0 (AES) because there were some changes
	// in the templates, etc... So once we have a valid/latest `AppVersion`, we must get the chart
	// with the highest `Version`.
	//
	var latest *repo.ChartVersion
	for _, curVer := range versions {
		allowed, err := lc.cvr.Allowed(curVer.AppVersion)
		if err != nil {
			return nil, fmt.Errorf("%w while checking if allowed for %s", err, lc.cvr)
		}
		if !allowed {
			log.V(3).Info("Chart not allowed by version constraint",
				"version", curVer.AppVersion, "versionRequired", lc.cvr)
			continue
		}
		if len(curVer.URLs) == 0 {
			return nil, fmt.Errorf("no URL found for %s-%s", chartName, lc.cvr)
		}

		// no previous `latest` chart: use this one
		if latest == nil {
			latest = curVer
			continue
		}

		// compare the versions: first, the `AppVersion`, and then the `Chart` version
		if moreRecent, err := MoreRecentThan(curVer.AppVersion, latest.AppVersion); err == nil && moreRecent {
			log.V(3).Info("Updating latest chart", "URL", curVer)
			latest = curVer
		} else if equal, err := Equal(curVer.AppVersion, latest.AppVersion); err == nil && equal {
			// if this chart has the same version of Ambassador, then check if it is a more recent Chart
			if moreRecent, err := MoreRecentThan(curVer.Version, latest.Version); err == nil && moreRecent {
				log.V(3).Info("Chart URL", "URL", curVer)
				latest = curVer
			}
		}
	}
	if latest != nil {
		return parsedURL(latest.URLs[0])
	}

	return nil, fmt.Errorf("no chart version found for %s-%s", chartName, lc.cvr)
}

// findChartDir looks for the directory that seems to contain a Chart
func (lc *HelmManager) findChartDir() (string, error) {
	res := ""

	if lc.downDir == "" {
		panic(fmt.Errorf("no downloads directory"))
	}

	_ = filepath.Walk(lc.downDir, func(path string, info os.FileInfo, err error) error {
		if res != "" {
			return nil
		}
		fi, err := os.Stat(path)
		if err != nil {
			return err
		}
		if fi.IsDir() {
			log := log.WithValues("directory", path)
			log.V(1).Info("Looking for Chart in directory")
			if validChart, _ := chartutil.IsChartDir(path); validChart {
				log.V(1).Info("Directory contains a Chart")
				res = path
			}
		}
		return nil
	})

	if res != "" {
		log.V(1).Info("Chart directory found", "directory", res)
		return res, nil
	}

	return "", fmt.Errorf("%w: %q", ErrNoChartDirFound, lc.downDir)
}
