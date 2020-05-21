package ambassadorinstallation

import (
	"errors"
	"fmt"
	"io/ioutil"

	"gopkg.in/yaml.v2"
)

var (
	errFileDoesNotExist = errors.New("values file does not exists")

	errParseError = errors.New("error when parsing YAML")
)

// readValues unserializes a values file
func readValues(in []byte) (HelmValues, error) {
	var output HelmValues

	if err := yaml.Unmarshal(in, &output); err != nil {
		return nil, fmt.Errorf("%w: %s", errParseError, in)
	}
	return output, nil
}

// readValuesFile reads a values.yaml file from disk
func readValuesFile(file string) (HelmValues, error) {
	if !fileExists(file) {
		return nil, errFileDoesNotExist
	}

	data, err := ioutil.ReadFile(file)
	if err != nil {
		return nil, err
	}

	return readValues(data)
}
