package ambassadorinstallation

import (
	"context"
	"errors"
	"time"

	"helm.sh/helm/v3/pkg/storage/driver"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/util/wait"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	ambassador "github.com/datawire/ambassador-operator/pkg/apis/getambassador/v2"
)

const (
	// timeout for performing a delete
	defaultDeleteTimeout = 5 * time.Minute
)

// deleteRelease deletes the current release
func (r *ReconcileAmbassadorInstallation) deleteRelease(o *unstructured.Unstructured, pendingFinalizers []string, chartsMgr HelmManager) (reconcile.Result, error) {
	updateDeadline := time.Now().Add(defaultDeleteTimeout)
	ctx, _ := context.WithDeadline(context.TODO(), updateDeadline)

	if !contains(pendingFinalizers, defFinalizerID) {
		log.Info("Resource is terminated, skipping reconciliation")
		return reconcile.Result{}, nil
	}

	manager, err := chartsMgr.GetManagerFor(o)
	defer func() { _ = chartsMgr.Cleanup() }()
	if err != nil {
		return reconcile.Result{}, err
	}

	status := ambassador.StatusFor(o)

	log.V(2).Info("Uninstalling release", "release", manager.ReleaseName())
	_, err = manager.UninstallRelease(ctx)
	if err != nil && !errors.Is(err, driver.ErrReleaseNotFound) {
		log.Error(err, "Failed to uninstall release")
		status.SetCondition(ambassador.AmbInsCondition{
			Type:    ambassador.ConditionReleaseFailed,
			Status:  ambassador.StatusTrue,
			Reason:  ambassador.ReasonUninstallError,
			Message: err.Error(),
		})
		_ = r.updateResourceStatus(o, status)
		return reconcile.Result{}, err
	}
	status.RemoveCondition(ambassador.ConditionReleaseFailed)

	if errors.Is(err, driver.ErrReleaseNotFound) {
		log.Info("Release not found, removing finalizer")
	} else {
		log.Info("Uninstalled release")
		status.SetCondition(ambassador.AmbInsCondition{
			Type:   ambassador.ConditionDeployed,
			Status: ambassador.StatusFalse,
			Reason: ambassador.ReasonUninstallSuccessful,
		})
		status.DeployedRelease = nil
	}
	if err := r.updateResourceStatus(o, status); err != nil {
		log.Info("Failed to update AmbassadorInstallation status")
		return reconcile.Result{}, err
	}

	finalizers := []string{}
	for _, pendingFinalizer := range pendingFinalizers {
		if pendingFinalizer != defFinalizerID {
			finalizers = append(finalizers, pendingFinalizer)
		}
	}
	o.SetFinalizers(finalizers)
	if err := r.updateResource(o); err != nil {
		log.Info("Failed to remove CR uninstall finalizer")
		return reconcile.Result{}, err
	}

	// Since the client is hitting a cache, waiting for the
	// deletion here will guarantee that the next reconciliation
	// will see that the AmbassadorInstallation has been deleted
	// and that there's nothing left to do.
	if err := r.waitForDeletion(o); err != nil {
		log.Info("Failed waiting for CR deletion")
		return reconcile.Result{}, err
	}
	return reconcile.Result{}, nil
}

// waitForDeletion waits for the
func (r *ReconcileAmbassadorInstallation) waitForDeletion(o runtime.Object) error {
	key, err := client.ObjectKeyFromObject(o)
	if err != nil {
		return err
	}

	ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
	defer cancel()

	return wait.PollImmediateUntil(time.Millisecond*10, func() (bool, error) {
		err := r.Client.Get(ctx, key, o)
		if apierrors.IsNotFound(err) {
			return true, nil
		}
		if err != nil {
			return false, err
		}
		return false, nil
	}, ctx.Done())
}
