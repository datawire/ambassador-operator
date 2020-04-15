package ambassadorinstallation

import (
	"testing"
)

func TestReadValues(t *testing.T) {
	contents := `
image.tag: v1.2
deploymentTool: amb-oper-azure
`

	contentsBytes := []byte(contents)
	values, err := readValues(contentsBytes)
	if err != nil {
		t.Fatal(err)
	}

	deploymentTool, ok := values["deploymentTool"]
	if !ok {
		t.Fatalf("Did not find expected key: %v", values)
	}
	if deploymentTool != "amb-oper-azure" {
		t.Fatalf("Did not find expected value: %v", deploymentTool)
	}

	imageTag, ok := values["image.tag"]
	if !ok {
		t.Fatalf("Did not find expected key: %v", values)
	}
	if imageTag != "v1.2" {
		t.Fatalf("Did not find expected value: %v", deploymentTool)
	}

	return
}
