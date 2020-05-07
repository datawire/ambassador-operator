package ambassadorinstallation

import (
	"fmt"
	"strings"

	"github.com/operator-framework/operator-sdk/pkg/helm/release"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"sigs.k8s.io/controller-runtime/pkg/manager"

	"github.com/datawire/ambassador/pkg/helm"
)

const (
	defHelmValuesFieldName = "helmValues"
)

// HelmValues is the values for the Helm chart
type HelmValues map[string]interface{}

// HelmValuesStrings is the values using only strings
type HelmValuesStrings map[string]string

// GetHelmValuesFrom returns a `.spec.helmValues` field if it exists, nil otherwise
func GetHelmValuesFrom(o *unstructured.Unstructured) HelmValues {
	spec, ok := o.Object["spec"].(map[string]interface{})
	if !ok {
		return nil
	}

	if helmValuesUntyped, ok := spec[defHelmValuesFieldName]; ok {
		if helmValues, ok := helmValuesUntyped.(map[string]interface{}); ok {
			return helmValues
		}
	}
	return nil
}

// HelmManager is a remote Helm repo or a file, provided with an URL
type HelmManager struct {
	mgr    manager.Manager
	Values HelmValuesStrings
	helm.HelmDownloader
}

type HelmManagerOptions struct {
	Manager manager.Manager
	helm.HelmDownloaderOptions
}

// NewHelmManager creates a new charts manager
// The Helm Manager will use the URL provided, and download (lazily) a Chart that
// obeys the Version Rule.
func NewHelmManager(options HelmManagerOptions, values HelmValuesStrings) (HelmManager, error) {
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

	// create a copy of the object. we will use this one for creating the manager.
	var oc unstructured.Unstructured
	o.DeepCopyInto(&oc)

	valuesStrings := lc.Values

	// hack for allowing any type in the helmValues:
	// translate all the `.spec.helmValues.*` to `.spec.*`, so factory.NewManager
	// will get these values (with any type) for setting.
	if helmValues := GetHelmValuesFrom(&oc); helmValues != nil {
		for k, v := range helmValues {
			if strings.Contains(k, ".") {
				// if we detect a dot then we pass it as a value for backwards-compatibility
				// for example, in `service.ports[0].port: 80`
				valuesStrings[k] = fmt.Sprintf("%v", v)
			} else {
				if err := unstructured.SetNestedField(oc.Object, v, "spec", k); err != nil {
					log.Info("could not set spec value", "key", k, "value", v)
				}
			}
		}
		unstructured.RemoveNestedField(oc.Object, "spec", defHelmValuesFieldName)
	}

	chartMgr, err := factory.NewManager(&oc, valuesStrings)
	if err != nil {
		return nil, err
	}

	return chartMgr, nil
}
