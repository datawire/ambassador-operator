package ambassadorinstallation

import (
	"crypto/md5"
	"encoding/base64"
	"encoding/json"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
)

const previousAppliedAnnot = "amb-operator/last-spec-hash"

// hasChangedSpec returns True iff the AmbassadorInstallation has a previous
// .spec recorded and the current .spec is different.
func hasChangedSpec(o *unstructured.Unstructured) bool {
	log.Info("Comparing changes with previously applied configuration")

	currSpecHash, err := getCurrSpecHash(o)
	if err != nil {
		log.Error(err, "when trying to get current .spec hash")
		return false
	}

	// make sure we update the last-hash annotation before returning
	defer setLastSpecHash(o, currSpecHash)

	log.Info("Saving current spec hash", "hash", currSpecHash)
	prevSpecHash, prevFound := getLastSpecHash(o)
	if !prevFound {
		log.Info("AmbassadorInstallation was not applied before")
		return false
	}
	if prevSpecHash == currSpecHash {
		log.Info("No changes detected in .spec")
		return false
	}

	log.Info("changes detected in .spec",
		"prevHash", prevSpecHash, "currHash", currSpecHash)
	return true
}

// getLastSpecHash returns the last .spec hash
func getLastSpecHash(o *unstructured.Unstructured) (string, bool) {
	prevStr, found := o.GetAnnotations()[previousAppliedAnnot]
	return prevStr, found
}

func getCurrSpecHash(o *unstructured.Unstructured) (string, error) {
	currSpec, _, err := getCurrSpec(o)
	if err != nil {
		return "", err
	}

	// encode the current .spec as a JSON
	encodedSpec, err := json.Marshal(currSpec)
	if err != nil {
		return "", err
	}

	// calculate the MD5 of the spec
	h := md5.New()
	s := base64.StdEncoding.EncodeToString(h.Sum(encodedSpec))

	return s, nil
}

// getCurrSpec returns the current .spec
func getCurrSpec(o *unstructured.Unstructured) (interface{}, bool, error) {
	currSpec, found, err := unstructured.NestedFieldNoCopy(o.Object, "spec")
	if !found {
		log.Error(err, "No .spec found in current AmbassadorInstallation")
		return nil, false, nil
	}
	if err != nil {
		log.Error(err, "when trying to get current .spec")
		return nil, true, err
	}

	return currSpec, true, nil
}

// setLastSpec sets the last .spec that has been processed in an annotation
func setLastSpecHash(o *unstructured.Unstructured, currSpecHash string) {
	annotations := o.GetAnnotations()
	annotations[previousAppliedAnnot] = currSpecHash
	o.SetAnnotations(annotations)
}
