package ambassadorinstallation

import (
	"errors"

	"github.com/go-test/deep"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
)

var (
	errNoPrevConfigFound = errors.New("no previous configuration found")
)

// hasChangedSpec returns True iff the AmbassadorInstallation has a previous
// .spec recorded and the current .spec is different.
func hasChangedSpec(o *unstructured.Unstructured) bool {
	log.Info("Comparing changes with previously applied configuration")

	prev, err := getLastApplied(o)
	if err == errNoPrevConfigFound {
		log.Info("AmbassadorInstallation was not applied before")
		return false
	}
	if err != nil {
		log.Error(err, "when trying to check previous spec")
		return false
	}

	currSpec, found, err := unstructured.NestedFieldNoCopy(o.Object, "spec")
	if !found {
		log.Error(err, "No .spec found in current AmbassadorInstallation")
		return false
	}
	if err != nil {
		log.Error(err, "when trying to get current .spec")
		return false
	}

	prevSpec, found, err := unstructured.NestedFieldNoCopy(prev.Object, "spec")
	if !found {
		log.Error(err, "No .spec found in previous AmbassadorInstallation")
		return false
	}
	if err != nil {
		log.Error(err, "when trying to get previous .spec")
		return false
	}

	if diff := deep.Equal(prevSpec, currSpec); diff != nil {
		log.Info("changes detected in .spec", "change", diff)
		return true
	}

	log.Info("No changes detected in .spec")
	return false
}

// getLastApplied returns the previously applied configuration
func getLastApplied(o *unstructured.Unstructured) (unstructured.Unstructured, error) {
	const previousAppliedAnnot = "kubectl.kubernetes.io/last-applied-configuration"
	prevStr, found := o.GetAnnotations()[previousAppliedAnnot]
	if !found {
		return unstructured.Unstructured{}, errNoPrevConfigFound
	}

	prev := unstructured.Unstructured{}
	_, _, err := unstructured.UnstructuredJSONScheme.Decode([]byte(prevStr), nil, &prev)
	if err != nil {
		return unstructured.Unstructured{}, err
	}
	return prev, nil
}
