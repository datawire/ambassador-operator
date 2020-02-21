package ambassadorinstallation

import (
	"testing"
	"time"
)

func TestUpdateWindowAllowed(t *testing.T) {
	defaultCheckInterval := 5 * time.Minute

	tests := []struct {
		name          string
		cron          string
		nowTime       time.Time
		checkInterval time.Duration
		expected      bool
	}{
		{
			name:          "updateWindow not specified, should always update",
			cron:          "",
			nowTime:       time.Date(2020, 1, 15, 10, 10, 10, 0, time.UTC),
			checkInterval: defaultCheckInterval,
			expected:      true,
		},
		{
			name:          "update every minute, should update",
			cron:          "* * * * *",
			nowTime:       time.Date(2020, 1, 15, 10, 10, 10, 0, time.UTC),
			checkInterval: defaultCheckInterval,
			expected:      true,
		},
		{
			name:          "update every hour, should not update",
			cron:          "0 * * * *",
			nowTime:       time.Date(2020, 1, 15, 10, 10, 10, 0, time.UTC),
			checkInterval: defaultCheckInterval,
			expected:      false,
		},
		{
			name:          "update every hour (next 3 minutes), should update",
			cron:          "0 * * * *",
			nowTime:       time.Date(2020, 1, 15, 10, 57, 10, 0, time.UTC),
			checkInterval: defaultCheckInterval,
			expected:      true,
		},
		{
			name:          "update every minute and Never, should not update",
			cron:          "* * * * *,Never",
			nowTime:       time.Date(2020, 1, 15, 10, 10, 10, 0, time.UTC),
			checkInterval: defaultCheckInterval,
			expected:      false,
		},
	}

	for _, test := range tests {
		t.Logf("Running test: %v", test.name)
		uw, err := NewUpdateWindow(test.cron)
		if err != nil {
			t.Errorf("Cannot create new update window: %v", err)
		}

		isAllowed := uw.Allowed(test.nowTime, test.checkInterval)
		if test.expected != isAllowed {
			t.Errorf("updateWindow allowed? Expected %v, got %v", test.expected, isAllowed)
		}
	}
}
