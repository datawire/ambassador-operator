package ambassadorinstallation

import (
	"context"
	"fmt"
	"time"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
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
func (r *ReconcileAmbassadorInstallation) tryInstallOrUpdate(ambObj *unstructured.Unstructured,
	chartsMgr HelmManager, window UpdateWindow, helmValues HelmValuesStrings, isMigrating bool, flavor string) (reconcile.Result, error) {
	updateDeadline := time.Now().Add(defaultUpdateTimeout)
	ctx, _ := context.WithDeadline(context.TODO(), updateDeadline)

	r.ReportEvent("start_install_or_update")

	now := time.Now()
	status := ambassador.StatusFor(ambObj)
	currCondition := status.LastCondition(ambassador.AmbInsCondition{})
	log.V(2).Info("Last condition",
		"type", currCondition.Type, "reason", currCondition.Reason, "status", currCondition.Status)

	// in general we will not check if we need to update until the next "update window"
	// however, some exceptions will cause to ignore this time:
	// 1) a migration from OSS to AES has been specified
	// 2) the .spec has changed
	ignoreTime := false
	if isMigrating || hasChangedSpec(ambObj) {
		ignoreTime = true
	}

	// when Ambassador is currently happily deployed, do not continue with this upgrade check if:
	// 1. we did this check not so long ago...
	// 2. this is not the right time (ie, not allowed by the update window)
	// try to install/upgrade in any other case (ie, the initial installation, the deployment
	// is in an error state, etc)
	// We ignore this upgrade check when OSS to AES migration is set in AmbassadorInstallation
	if (currCondition.Type == ambassador.ConditionDeployed) && !ignoreTime {
		if !status.LastCheckTime.Time.IsZero() && now.Sub(status.LastCheckTime.Time) < r.updateInterval {
			log.Info("Last install/update was not so long ago", "updateInterval", r.updateInterval)
			return reconcile.Result{RequeueAfter: r.checkInterval}, nil
		}

		if !window.Allowed(now, r.checkInterval) {
			log.V(2).Info("Update not allowed by window", "window", window)
			return reconcile.Result{RequeueAfter: r.checkInterval}, nil
		}
	}

	// if we are supposed to migrate, check that the migration can be done (ie, no AuthService)
	if isMigrating {
		res, err := r.canMigrate(ambObj)
		if err != nil {
			return res, err
		}
	}

	if err := chartsMgr.Download(); err != nil {
		// report to Metriton & log
		r.ReportError("fail_release_download", "Failed to download latest release", err)

		status.SetCondition(ambassador.AmbInsCondition{
			Type:    ambassador.ConditionReleaseFailed,
			Status:  ambassador.StatusTrue,
			Reason:  ambassador.ReasonDownloadError,
			Message: err.Error(),
		})

		_ = r.updateResourceStatus(ambObj, status)
		return reconcile.Result{RequeueAfter: r.checkInterval}, err
	}
	defer func() { _ = chartsMgr.Cleanup() }()

	chart, err := chartsMgr.GetManagerFor(ambObj, helmValues)
	defer func() { _ = chartsMgr.Cleanup() }()
	if err != nil {
		message := "when obtaining the chart manager"
		log.Error(err, message)
		return reconcile.Result{RequeueAfter: r.checkInterval}, err
	}
	log := log.WithValues("release", chart.ReleaseName())

	if err := chart.Sync(ctx); err != nil {
		// Report to Metriton & log
		r.ReportError("fail_no_sync", "Failed to sync release", err)

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

		installedRelease, err := chart.InstallRelease(ctx)

		if err != nil {
			// Report to Metriton & log
			r.ReportError("fail_no_install", "Installation of a new release failed", err)

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

		message := "New release installed successfully"

		log.Info(message)
		//if log.V(0).Enabled() {
		//	fmt.Println(diffutil.Diff("", installedRelease.Manifest))
		//}
		log.V(1).Info("Config values", "values", installedRelease.Config)

		if installedRelease.Info != nil {
			message = installedRelease.Info.Notes
		}

		// Report successful install!
		r.ReportEvent("reconcile_install_complete",
			ScoutMeta{"message", message})

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
			Flavor:     flavor,
		}

		err = r.updateResourceStatus(ambObj, status)
		return reconcile.Result{RequeueAfter: r.checkInterval}, err
	}

	if chart.IsUpdateRequired() {
		log.Info("Ambassador is currently installed, but an upgrade is required",
			"newVersion", chartsMgr.GetVersionRule().String())

		previousRelease, updatedRelease, err := chart.UpdateRelease(ctx)
		if err != nil {
			// Report to Metriton & log
			r.ReportError("fail_update_release", "Release failed", err)

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

		// Report successful update to Metriton
		r.ReportEvent("completed_update",
			ScoutMeta{"message", message})

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
			Flavor:     flavor,
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
		// Report to Metriton & log
		r.ReportError("fail_reconciliation", "Failed to reconcile release", err)

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

	// Reconciled release!
	message := "Reconciled release"

	// Report to Metriton
	r.ReportEvent("completed_reconciliation",
		ScoutMeta{"message", message})

	// ... and log it
	log.Info(message)

	status.DeployedRelease = &ambassador.AmbassadorRelease{
		Name:       expectedRelease.Name,
		Version:    expectedRelease.Chart.Metadata.Version,
		AppVersion: expectedRelease.Chart.Metadata.AppVersion,
		Manifest:   expectedRelease.Manifest,
		Flavor:     flavor,
	}

	_ = r.updateResourceStatus(ambObj, status)
	return reconcile.Result{RequeueAfter: r.checkInterval}, nil
}

// canMigrate verifies that the migration can be performed, returning an error otherwise
func (r *ReconcileAmbassadorInstallation) canMigrate(ambIns *unstructured.Unstructured) (reconcile.Result, error) {
	status := ambassador.StatusFor(ambIns)
	namespace := ambIns.GetNamespace()

	resultError := func(message string, event string) (reconcile.Result, error) {
		err := fmt.Errorf(message)
		log.Error(err, "")

		status.SetCondition(ambassador.AmbInsCondition{
			Type:    ambassador.ConditionReleaseFailed,
			Status:  ambassador.StatusTrue,
			Reason:  ambassador.ReasonUpgradePrecondError,
			Message: message,
		})
		_ = r.updateResourceStatus(ambIns, status)
		r.ReportError(event, message, err)
		return reconcile.Result{RequeueAfter: r.checkInterval}, err
	}

	log.Info("Checking for AuthService...")
	authServiceList, err := r.lookupResourceList(&schema.GroupVersionKind{
		Group:   "getambassador.io",
		Version: "v2",
		Kind:    "AuthService",
	}, namespace)
	if err != nil {
		return resultError("could not look up AuthService in the cluster", "fail_no_authservice")
	}
	if len(authServiceList.Items) > 0 {
		return resultError("AuthService(s) exist in the cluster, please remove to upgrade to AES", "fail_existing_authservice")
	}

	log.Info("Checking for RateLimitService...")
	rateLimitServiceList, err := r.lookupResourceList(&schema.GroupVersionKind{
		Group:   "getambassador.io",
		Version: "v2",
		Kind:    "RateLimitService",
	}, namespace)
	if err != nil {
		return resultError("could not look up RateLimitService in the cluster", "fail_no_ratelimitservice")
	}
	if len(rateLimitServiceList.Items) > 0 {
		return resultError("RateLimitService(s) exist in the cluster, please remove to upgrade to AES", "fail_existing_ratelimitservice")
	}

	return reconcile.Result{}, nil
}
