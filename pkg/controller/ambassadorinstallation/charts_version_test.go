package ambassadorinstallation

import (
	"testing"
)

func TestChartVersionRule_Basic(t *testing.T) {
	rule, err := NewChartVersionRule("*")
	if err != nil {
		t.Errorf("Could not create chart version rule: %s", err)
	}

	if res, err := rule.Allowed("1.0"); err != nil || res == false {
		t.Errorf("Version 1.0 should be allowed")
	}

	// check a different rule
	rule, err = NewChartVersionRule("2.*")
	if err != nil {
		t.Errorf("Could not create chart version rule: %s", err)
	}

	if res, err := rule.Allowed("1.0"); err != nil || res == true {
		t.Errorf("Version 1.0 should NOT be allowed")
	}
	if res, err := rule.Allowed("2.5"); err != nil || res == false {
		t.Errorf("Version 2.5 should be allowed")
	}
}

func TestChartVersionRule_MoreRecentThan(t *testing.T) {
	type versionComparision struct {
		a         string
		b         string
		expResult bool
	}

	tests := []versionComparision{
		{"1.0", "2.0", false},
		{"2.0", "1.0", true},
		{"1.1", "1.0", true},
		{"1.0.1", "1.0", true},
		{"1.0.0", "1.0.1", false},
	}

	for _, test := range tests {
		res, err := MoreRecentThan(test.a, test.b)
		if err != nil {
			t.Errorf("Error when checking if %s > %s: %s", test.a, test.b, err)
		}
		if res != test.expResult {
			t.Errorf("When checking if %s > %s: unexpected result", test.a, test.b)
		}
	}
}

func TestChartVersionRule_Equal(t *testing.T) {
	type versionComparision struct {
		a         string
		b         string
		expResult bool
	}

	tests := []versionComparision{
		{"1.0", "1.0", true},
		{"2.1", "2.1", true},
		{"1.1.1", "1.1.1", true},
		{"9.0", "8.0", false},
	}

	for _, test := range tests {
		res, err := Equal(test.a, test.b)
		if err != nil {
			t.Errorf("Error when checking if %s == %s: %s", test.a, test.b, err)
		}
		if res != test.expResult {
			t.Errorf("When checking if %s == %s: unexpected result", test.a, test.b)
		}
	}
}
