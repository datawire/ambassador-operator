package ambassadorinstallation

import (
	"testing"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
)

func TestHelmValues(t *testing.T) {
	ambIns := &unstructured.Unstructured{
		Object: map[string]interface{}{
			"spec": map[string]interface{}{
				"helmValues": map[string]interface{}{
					"deploymentTool": "amb-oper-kind",
				},
			},
		},
	}

	hv := GetHelmValuesAmbIns(ambIns)
	res, found, err := hv.GetString("deploymentTool")
	if err != nil {
		t.Errorf("error while looking for deploymentTool: %v", err)
	}
	if !found {
		t.Errorf("deploymentTool not found")
	}
	if res != "amb-oper-kind" {
		t.Errorf("deploymentTool %q does not match expected values 'amb-oper-kind'", res)
	}

	// add some new helmValues, overwriting some of the old ones
	newHelmValues := map[string]interface{}{
		"deploymentTool":   "amb-oper-manifest",
		"image.repository": "somewhere",
	}
	hv.AppendFrom(newHelmValues, true)

	res, found, err = hv.GetString("deploymentTool")
	if err != nil {
		t.Errorf("error while looking for deploymentTool: %v", err)
	}
	if !found {
		t.Errorf("deploymentTool not found")
	}
	if res != "amb-oper-manifest" {
		t.Errorf("deploymentTool %q does not match expected values 'amb-oper-manifest'", res)
	}

	res, found, err = hv.GetString("image.repository")
	if err != nil {
		t.Errorf("error while looking for image.repository: %v", err)
	}
	if !found {
		t.Errorf("image.repository not found")
	}
	if res != "somewhere" {
		t.Errorf("image.repository %q does not match expected values 'somewhere'", res)
	}

	return
}
