package ambassadorinstallation

import (
	"fmt"
	"github.com/gorhill/cronexpr"
	"strings"
	"time"
)

const (
	AlwaysUpdate updatePriority = "always"
	NeverUpdate  updatePriority = "never"
)

type updatePriority string

// UpdateWindow is a update window definition
type UpdateWindow struct {
	s              string // string representation (used just for the Stringer)
	intervals      []string
	updatePriority updatePriority // true if updates are always allowed, false if never allowed
}

// NewUpdateWindow return s a new update window after parsing the definition provided
func NewUpdateWindow(def string) (UpdateWindow, error) {
	// There can be any number of updateWindow entries (separated by commas).
	//
	// - “Never” turns off automatic updates even if there are other entries in the
	//  comma-separated list. Never is used by sysadmins to disable all updates during
	//  blackout periods by doing a kubectl apply or using our Edge Policy Console to set this.
	//
	// - “Hh:mm-hh:mm TZ” sets the update window to these times in this timezone.
	// - “day hh:mm-day hh:mm TZ” sets the update window to these times on these
	//  days in this timezone. The “day” can either be the numeric days of the month e.g.
	//  “3 23:00-4 01:59 ET” is the 3rd of each month from 11pm ET to the 4th of the each
	//  month 2am ET (three hours); or the “day” can be english names of days e.g.
	// “Sat 10:00-Sat 11:00 ET” which means Sat from 10am to 11am ET every week.
	//

	updateWindow := UpdateWindow{}

	// If no updateWindow is specified by the user, then it's allowed to update at all times
	if len(def) == 0 {
		updateWindow.updatePriority = AlwaysUpdate
	}

	allWindows := strings.Split(def, ",")

	// If there is a "Never" in any one of the update windows, we will never update
	for _, window := range allWindows {
		if strings.ToLower(window) == "never" {
			updateWindow.updatePriority = NeverUpdate
			break
		}
	}

	updateWindow.intervals = allWindows

	return updateWindow, nil
}

// Allowed returns True if the update is allowed now
func (u UpdateWindow) Allowed(now time.Time, checkInterval time.Duration) bool {
	if u.updatePriority == AlwaysUpdate {
		log.Info("Update is always allowed")
		return true
	} else if u.updatePriority == NeverUpdate {
		log.Info("Update is never allowed")
		return false
	}

	updateNow := false
	for _, window := range u.intervals {
		expression, err := cronexpr.Parse(window)
		if err != nil {
			log.Error(err, fmt.Sprintf("Could not parse updateWindow: %v", window))
			return false
		}

		// nextUpdateTime is when the update will be processed next
		nextUpdateTime := expression.Next(now)

		// nextRunTime is when the reconcile loop will be run next
		nextRunTime := now.Add(checkInterval)

		// If nextUpdateTime happens between now and nextRunTime, then we update now.
		if nextUpdateTime.Before(nextRunTime) && nextUpdateTime.After(now) {
			log.Info(fmt.Sprintf("Update scheduled for window %v is being performed now", window))
			updateNow = true
			// Not adding a break here because we'd like to see logs from all update windows here
		} else {
			log.Info(fmt.Sprintf("Update for window %v will be performed in later reconciliation cycles", window))
		}

		log.Info(fmt.Sprintf("Check interval is: %v", checkInterval))
	}
	return updateNow
}

// String returns the string representation of the update window
func (u UpdateWindow) String() string {
	return u.s
}
