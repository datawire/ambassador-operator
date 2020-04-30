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

func readValues(in []byte) (HelmValuesStrings, error) {
	var output HelmValuesStrings

	if err := yaml.Unmarshal(in, &output); err != nil {
		return nil, fmt.Errorf("%w: %s", errParseError, in)
	}
	return output, nil
}

func readValuesFile(file string) (HelmValuesStrings, error) {
	if !fileExists(file) {
		return nil, errFileDoesNotExist
	}

	data, err := ioutil.ReadFile(file)
	if err != nil {
		return nil, err
	}

	return readValues(data)
}
