package ambassadorinstallation

import (
	"github.com/operator-framework/operator-sdk/pkg/helm/release"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"sigs.k8s.io/controller-runtime/pkg/manager"

	"github.com/datawire/ambassador/pkg/helm"
)

// HelmValues is the values for the Helm chart
type HelmValues map[string]string

// HelmManager is a remote Helm repo or a file, provided with an URL
type HelmManager struct {
	mgr    manager.Manager
	Values map[string]string
	helm.HelmDownloader
}

type HelmManagerOptions struct {
	Manager manager.Manager
	helm.HelmDownloaderOptions
}

// NewHelmManager creates a new charts manager
// The Helm Manager will use the URL provided, and download (lazily) a Chart that
// obeys the Version Rule.
func NewHelmManager(options HelmManagerOptions, values map[string]string) (HelmManager, error) {
	downloader, err := helm.NewHelmDownloader(options.HelmDownloaderOptions)
	if err != nil {
		return HelmManager{}, err
	}
	return HelmManager{
		mgr:            options.Manager,
		Values:         values,
		HelmDownloader: downloader,
	}, nil
}

// GetManagerFor returns a helm chart manager for the chart we have downloaded
func (lc *HelmManager) GetManagerFor(o *unstructured.Unstructured) (release.Manager, error) {

	factory := release.NewManagerFactory(lc.mgr, lc.DownChartDir)
	chartMgr, err := factory.NewManager(o, lc.Values)
	if err != nil {
		return nil, err
	}

	return chartMgr, nil
}
