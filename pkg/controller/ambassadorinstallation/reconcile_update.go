package ambassadorinstallation

import (
	"context"
	"time"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	ambassador "github.com/datawire/ambassador-operator/pkg/apis/getambassador/v2"
)

// note: base on the code of the Helm operator:
// https://github.com/operator-framework/operator-sdk/blob/master/pkg/helm/controller/reconcile.go

const (
	// default granularity for doing the updates operations
	defaultCheckInterval = 5 * time.Minute

	// we will try to update every "defaultUpdateInterval" seconds
	// however, if something fails, we will try again in "defaultCheckInterval" seconds
	defaultUpdateInterval = 24 * time.Hour

	// environ var that overrides the check interval (in seconds)
	defaultCheckIntervalEnvVar = "AMB_CHECK_INTERVAL"

	// environ var that overrides the update interval (in seconds)
	defaultUpdateIntervalEnvVar = "AMB_UPDATE_INTERVAL"

	// timeout for performing the update
	defaultUpdateTimeout = 5 * time.Minute
)

// tryInstallOrUpdate checks if we need to update the Helm chart
func (r *ReconcileAmbassadorInstallation) tryInstallOrUpdate(ambObj *unstructured.Unstructured, chartsMgr HelmManager, window UpdateWindow) (reconcile.Result, error) {
	updateDeadline := time.Now().Add(defaultUpdateTimeout)
	ctx, _ := context.WithDeadline(context.TODO(), updateDeadline)

	now := time.Now()
	status := ambassador.StatusFor(ambObj)
	currCondition := status.LastCondition(ambassador.AmbInsCondition{})
	log.V(2).Info("Last condition",
		"type", currCondition.Type, "reason", currCondition.Reason, "status", currCondition.Status)

	// when Ambassador is currently happily deployed, do not continue with this upgrade check if:
	// 1. we did this check not so long ago...
	// 2. this is not the right time (ie, not allowed by the update window)
	// try to install/upgrade in any other case (ie, the initial installation, the deployment
	// is in an error state, etc)
	if currCondition.Type == ambassador.ConditionDeployed {
		if !status.LastCheckTime.Time.IsZero() && now.Sub(status.LastCheckTime.Time) < r.updateInterval {
			log.Info("Last install/update was not so long ago", "updateInterval", r.updateInterval)
			return reconcile.Result{RequeueAfter: r.checkInterval}, nil
		}

		if !window.Allowed(now, r.checkInterval) {
			log.V(2).Info("Update not allowed by window", "window", window)
			return reconcile.Result{RequeueAfter: r.checkInterval}, nil
		}
	}

	chart, err := chartsMgr.GetManagerFor(ambObj)
	defer func() { _ = chartsMgr.Cleanup() }()
	if err != nil {
		log.Error(err, "when obtaining the chart manager")
		return reconcile.Result{RequeueAfter: r.checkInterval}, err
	}
	log := log.WithValues("release", chart.ReleaseName())

	if err := chart.Sync(ctx); err != nil {
		log.Error(err, "Failed to sync release")
		status.SetCondition(ambassador.AmbInsCondition{
			Type:    ambassador.ConditionIrreconcilable,
			Status:  ambassador.StatusTrue,
			Reason:  ambassador.ReasonReconcileError,
			Message: err.Error(),
		})
		_ = r.updateResourceStatus(ambObj, status)
		return reconcile.Result{RequeueAfter: r.checkInterval}, err
	}
	status.RemoveCondition(ambassador.ConditionIrreconcilable)
	status.TimestampCheck(now)

	if !chart.IsInstalled() {
		log.Info("Ambassador is not currently installed: installing...",
			"newVersion", chartsMgr.GetVersionRule().String())
		for k, v := range chartsMgr.GetValues() {
			r.EventRecorder.Eventf(ambObj, "Warning", "OverrideValuesInUse",
				"Chart value %q overridden to %q by Ambassador operator", k, v)
		}
		installedRelease, err := chart.InstallRelease(ctx)
		if err != nil {
			log.Error(err, "Installation of a new release failed")

			status.SetCondition(ambassador.AmbInsCondition{
				Type:    ambassador.ConditionReleaseFailed,
				Status:  ambassador.StatusTrue,
				Reason:  ambassador.ReasonInstallError,
				Message: err.Error(),
			})
			_ = r.updateResourceStatus(ambObj, status)
			return reconcile.Result{}, err
		}
		status.RemoveCondition(ambassador.ConditionReleaseFailed)

		if r.releaseHook != nil {
			if err := r.releaseHook(installedRelease); err != nil {
				log.Error(err, "Failed to run release hook")
				return reconcile.Result{}, err
			}
		}

		log.Info("New release installed successfully")
		//if log.V(0).Enabled() {
		//	fmt.Println(diffutil.Diff("", installedRelease.Manifest))
		//}
		log.V(1).Info("Config values", "values", installedRelease.Config)

		message := ""
		if installedRelease.Info != nil {
			message = installedRelease.Info.Notes
		}
		status.SetCondition(ambassador.AmbInsCondition{
			Type:    ambassador.ConditionDeployed,
			Status:  ambassador.StatusTrue,
			Reason:  ambassador.ReasonInstallSuccessful,
			Message: message,
		})
		status.DeployedRelease = &ambassador.AmbassadorRelease{
			Name:       installedRelease.Name,
			Version:    installedRelease.Chart.Metadata.Version,
			AppVersion: installedRelease.Chart.Metadata.AppVersion,
			Manifest:   installedRelease.Manifest,
		}

		err = r.updateResourceStatus(ambObj, status)
		return reconcile.Result{RequeueAfter: r.checkInterval}, err
	}

	if chart.IsUpdateRequired() {
		log.Info("Ambassador is currently installed, but an upgrade is required",
			"newVersion", chartsMgr.GetVersionRule().String())

		for k, v := range chartsMgr.GetValues() {
			r.EventRecorder.Eventf(ambObj, "Warning", "OverrideValuesInUse",
				"Chart value %q overridden to %q by Ambassador operator", k, v)
		}

		previousRelease, updatedRelease, err := chart.UpdateRelease(ctx)
		if err != nil {
			log.Error(err, "Release failed")
			status.SetCondition(ambassador.AmbInsCondition{
				Type:    ambassador.ConditionReleaseFailed,
				Status:  ambassador.StatusTrue,
				Reason:  ambassador.ReasonUpdateError,
				Message: err.Error(),
			})
			_ = r.updateResourceStatus(ambObj, status)
			return reconcile.Result{}, err
		}
		log.Info("Update required", "previousVersion", previousRelease.Version, "nextVersion", updatedRelease.Version)
		log.Info("Previous version", "firstDeployed", previousRelease.Info.FirstDeployed, "status", previousRelease.Info.Status)
		status.RemoveCondition(ambassador.ConditionReleaseFailed)

		if r.releaseHook != nil {
			if err := r.releaseHook(updatedRelease); err != nil {
				log.Error(err, "Failed to run release hook")
				return reconcile.Result{}, err
			}
		}

		log.Info("Updated release")
		//if log.V(0).Enabled() {
		//	fmt.Println(diffutil.Diff(previousRelease.Manifest, updatedRelease.Manifest))
		//}
		log.V(1).Info("Config values", "values", updatedRelease.Config)

		message := ""
		if updatedRelease.Info != nil {
			message = updatedRelease.Info.Notes
		}
		status.SetCondition(ambassador.AmbInsCondition{
			Type:    ambassador.ConditionDeployed,
			Status:  ambassador.StatusTrue,
			Reason:  ambassador.ReasonUpdateSuccessful,
			Message: message,
		})

		status.DeployedRelease = &ambassador.AmbassadorRelease{
			Name:       updatedRelease.Name,
			Version:    updatedRelease.Chart.Metadata.Version,
			AppVersion: updatedRelease.Chart.Metadata.AppVersion,
			Manifest:   updatedRelease.Manifest,
		}
		err = r.updateResourceStatus(ambObj, status)
		return reconcile.Result{RequeueAfter: r.checkInterval}, err
	}

	// If a change is made to the CR spec that causes a release failure, a
	// ConditionReleaseFailed is added to the status conditions. If that change
	// is then reverted to its previous state, the operator will stop
	// attempting the release and will resume reconciling. In this case, we
	// need to remove the ConditionReleaseFailed because the failing release is
	// no longer being attempted.
	status.RemoveCondition(ambassador.ConditionReleaseFailed)

	expectedRelease, err := chart.ReconcileRelease(ctx)
	if err != nil {
		log.Error(err, "Failed to reconcile release")
		status.SetCondition(ambassador.AmbInsCondition{
			Type:    ambassador.ConditionIrreconcilable,
			Status:  ambassador.StatusTrue,
			Reason:  ambassador.ReasonReconcileError,
			Message: err.Error(),
		})
		_ = r.updateResourceStatus(ambObj, status)
		return reconcile.Result{RequeueAfter: r.checkInterval}, err
	}
	status.RemoveCondition(ambassador.ConditionIrreconcilable)

	if r.releaseHook != nil {
		if err := r.releaseHook(expectedRelease); err != nil {
			log.Error(err, "Failed to run release hook")
			return reconcile.Result{RequeueAfter: r.checkInterval}, err
		}
	}

	log.Info("Reconciled release")
	status.DeployedRelease = &ambassador.AmbassadorRelease{
		Name:       expectedRelease.Name,
		Version:    expectedRelease.Chart.Metadata.Version,
		AppVersion: expectedRelease.Chart.Metadata.AppVersion,
		Manifest:   expectedRelease.Manifest,
	}
	_ = r.updateResourceStatus(ambObj, status)
	return reconcile.Result{RequeueAfter: r.checkInterval}, nil
}
