package ambassadorinstallation

import (
	"k8s.io/apimachinery/pkg/types"
)

// Initialize the Scout instance and reset.
func (r *ReconcileAmbassadorInstallation) BeginReporting(mode string, installID types.UID) {
	r.Scout = NewScout(mode, installID)
}

// ReportEvent sends an event to Metriton
func (r *ReconcileAmbassadorInstallation) ReportEvent(eventName string, meta ...ScoutMeta) {
	log.Info("[Metrics]", "event", eventName)
	if err := r.Scout.Report(eventName, meta...); err != nil {
		log.Info("[Metrics]", "event", eventName, "error", err)
	}
}

// Utility function for reporting an error with a message and an error code,
// sending the message and error in metadata.  Also logs it to the error log.
func (r *ReconcileAmbassadorInstallation) ReportError(eventName string, message string, err error) {
	// Send to Metriton
	r.ReportEvent(eventName,
		ScoutMeta{"message", message},
		ScoutMeta{"error", err})

	// send to the error log
	log.Error(err, message)
}
