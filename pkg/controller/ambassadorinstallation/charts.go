package ambassadorinstallation

import (
	"fmt"
	"strings"

	"github.com/operator-framework/operator-sdk/pkg/helm/release"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"sigs.k8s.io/controller-runtime/pkg/manager"

	"github.com/datawire/ambassador-operator/pkg/helm"
)

const (
	defHelmValuesFieldName = "helmValues"
)

var (
	defHelmValuesFullPath = []string{"spec", defHelmValuesFieldName}
)

// there are two different "helm values":
//
// - regular helm values: they are typed, and can be expressed as a tree.
// - "compact" (or string) values: they use the format used in `helm install --set`,
//   separating nodes in a tree with dots. They are not typed, and the
//   right side of the assignment is interpreted as a string.
//
// we must support the "compact" values for backwards compatibility

// HelmValues is the values for the Helm chart
type HelmValues map[string]interface{}

// GetHelmValuesAmbIns returns a `.spec.helmValues` field if it exists, nil otherwise
func GetHelmValuesAmbIns(ambIns *unstructured.Unstructured) HelmValues {
	helmValues, found, err := unstructured.NestedMap(ambIns.Object, defHelmValuesFullPath...)
	if err != nil || !found {
		return nil
	}
	return helmValues
}

// GetString gets a string value from the Helm values
func (hv HelmValues) GetString(k string) (string, bool, error) {
	ambIns := &unstructured.Unstructured{
		Object: map[string]interface{}{
			"spec": map[string]interface{}{
				defHelmValuesFieldName: (map[string]interface{})(hv),
			},
		},
	}
	return unstructured.NestedString(ambIns.Object, append(defHelmValuesFullPath, k)...)
}

// AppendFrom appends all the `other` helm values
func (hv *HelmValues) AppendFrom(other HelmValues, overwrite bool) {
	for k, v := range other {
		_, found := (*hv)[k]
		if found && !overwrite {
			continue
		}
		(*hv)[k] = v
	}
}

// WriteToAmbIns appends the values in an existing `.spec.helmValues` in a AmbassadorInstallation
// (optionally overwritting values)
func (hv HelmValues) WriteToAmbIns(ambIns *unstructured.Unstructured, overwrite bool) error {
	for k, v := range hv {
		fullPath := append(defHelmValuesFullPath, k)

		log.Info("Settings helmValue", "var", k, "value", v)
		_, found, err := unstructured.NestedFieldNoCopy(ambIns.Object, fullPath...)
		if err != nil {
			continue
		}

		// TODO: this does not perform a DeepCopy merge of existing-value with new-value
		if found && !overwrite {
			continue
		}
		_ = unstructured.SetNestedField(ambIns.Object, v, fullPath...)
	}
	return nil
}

// HelmValuesStrings is the values using only strings
type HelmValuesStrings map[string]string

// HelmManager is a remote Helm repo or a file, provided with an URL
type HelmManager struct {
	mgr manager.Manager
	helm.HelmDownloader
}

type HelmManagerOptions struct {
	Manager manager.Manager
	helm.HelmDownloaderOptions
}

// NewHelmManager creates a new charts manager
// The Helm Manager will use the URL provided, and download (lazily) a Chart that
// obeys the Version Rule.
func NewHelmManager(options HelmManagerOptions) (HelmManager, error) {
	downloader, err := helm.NewHelmDownloader(options.HelmDownloaderOptions)
	if err != nil {
		return HelmManager{}, err
	}
	return HelmManager{
		mgr:            options.Manager,
		HelmDownloader: downloader,
	}, nil
}

// GetManagerFor returns a helm chart manager for the chart we have downloaded
func (lc *HelmManager) GetManagerFor(o *unstructured.Unstructured, values HelmValuesStrings) (release.Manager, error) {
	factory := release.NewManagerFactory(lc.mgr, lc.GetChartDirectory())

	// create a copy of the object. we will use this one for creating the manager.
	var oc unstructured.Unstructured
	o.DeepCopyInto(&oc)

	valuesStrings := values

	// hack for allowing any type in the helmValues:
	// translate all the `.spec.helmValues.*` to `.spec.*`, so factory.NewManager
	// will get these values (with any type) for setting.
	if helmValues := GetHelmValuesAmbIns(&oc); helmValues != nil {
		for k, v := range helmValues {
			if strings.Contains(k, ".") {
				// if we detect a dot then we pass it as a value for backwards-compatibility
				// for example, in `service.ports[0].port: 80`
				vs := fmt.Sprintf("%v", v)
				log.Info("setting packed-form value", "key", k, "value", vs)
				valuesStrings[k] = vs
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
