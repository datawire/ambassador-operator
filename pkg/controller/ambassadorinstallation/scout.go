// From ambassador/internal/pkg/edgectl/scout.go with some modifications.

package ambassadorinstallation

import (
"fmt"

"github.com/google/uuid"
"github.com/pkg/errors"
"github.com/datawire/ambassador-operator/version"
"github.com/datawire/ambassador/pkg/metriton"
)

// The Scout structure maintains an index, which is the count of calls
// to Report, incrementing each call.  This provides a sequence of actions
// to make it easier to search through the reports.
// The Reporter is simply the Metriton reporting object.
type Scout struct {
	index    int
	Reporter *metriton.Reporter
}

// Metadata is simply a key and an untyped value, passed in as a parameter
// to (s *Scout) Report
type ScoutMeta struct {
	Key   string
	Value interface{}
}

// Create a new Scout object, with a parameter stating what the Scout instance
// will be reporting on.  The Ambassador Operator may be installing, updating,
// or deleting the Ambassador installation.
// @Alvaro please check that this is correct

func NewScout(mode string) (s *Scout) {
	return &Scout{
		Reporter: &metriton.Reporter{
			Application: "operator",
			Version:     version.Version,
			GetInstallID: func(r *metriton.Reporter) (string, error) {
				id, err := metriton.InstallIDFromFilesystem(r)
				if err != nil {
					id = "00000000-0000-0000-0000-000000000000"
					r.BaseMetadata["new_install"] = true
					r.BaseMetadata["install_id_error"] = err.Error()
				}
				return id, nil
			},
			// Fixed (growing) metadata passed with every report
			BaseMetadata: map[string]interface{}{
				"mode":     mode,
				"trace_id": uuid.New().String(),
			},
		},
	}
}

// Utility function to set a particular key/value metadata pair.
func (s *Scout) SetMetadatum(key string, value interface{}) {
	oldValue, ok := s.Reporter.BaseMetadata[key]
	if ok {
		panic(fmt.Sprintf("trying to replace metadata[%q] = %q with %q", key, oldValue, value))
	}
	s.Reporter.BaseMetadata[key] = value
}

// Reporting out: Sends a report to Metriton which will create a new entry in the
// Metriton database in the product_event table.
func (s *Scout) Report(action string, meta ...ScoutMeta) error {
	// Construct the report's metadata. Include the fixed (growing) set of
	// metadata in the Scout structure and the pairs passed as arguments to this
	// call. Also include and increment the index, which can be used to
	// determine the correct order of reported events for this installation
	// attempt (correlated by the trace_id set at the start).
	s.index++
	metadata := map[string]interface{}{
		"action": action,
		"index":  s.index,
	}
	for _, metaItem := range meta {
		metadata[metaItem.Key] = metaItem.Value
	}

	_, err := s.Reporter.Report(context.TODO(), metadata)
	if err != nil {
		return errors.Wrap(err, "scout report")
	}
	// TODO: Do something useful (alert the user if there's an available
	// upgrade?) with the response (discarded as "_" above)?

	return nil
}
