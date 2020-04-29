package ambassadorinstallation

import (
	"context"
	"fmt"
	"time"

	rpb "helm.sh/helm/v3/pkg/release"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/manager"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	ambassador "github.com/datawire/ambassador-operator/pkg/apis/getambassador/v2"
	"github.com/datawire/ambassador/pkg/helm"
)

// note: base on the code of the Helm operator:
// https://github.com/operator-framework/operator-sdk/blob/master/pkg/helm/controller/reconcile.go

// blank assignment to verify that ReconcileAmbassadorInstallation implements reconcile.Reconciler
var _ reconcile.Reconciler = &ReconcileAmbassadorInstallation{}

// ReleaseHookFunc defines a function signature for release hooks.
type ReleaseHookFunc func(*rpb.Release) error

const (
	// finalizer ID
	defFinalizerID = "uninstall-amb-operator-release"

	// controller name for the events recorder
	defControllerName = "ambassador-controller"
)

var (
	// some default Helm values
	defaultChartValues = map[string]string{
		"deploymentTool": "amb-oper",
	}

	// defExtraValuesFiles defines a list of files where we can find extra values
	// NOTE: values in the last files will overwrite values in previous files!
	defExtraValuesFiles = []string{
		"/etc/helm/values.yaml",
		"/tmp/helm/values.yaml",
		"/etc/values.yaml",
		"/tmp/values.yaml",
		"/tmp/cloud-values.yaml",
		"/tmp/cloud-values.yaml",
	}
)

var (
	// DefaultGVK is the GVK used by the AmbassadorInstallation
	// TODO: we should get these details from the CRD or somewhere...
	DefaultGVK = schema.GroupVersionKind{
		Group:   "getambassador.io",
		Version: "v2",
		Kind:    "AmbassadorInstallation",
	}
)

// ReconcileAmbassadorInstallation reconciles a AmbassadorInstallation object
type ReconcileAmbassadorInstallation struct {
	// This Client, initialized using mgr.Client() above, is a split Client
	// that reads objects from the cache and writes to the apiserver
	Client  client.Client
	Scheme  *runtime.Scheme
	Manager manager.Manager

	EventRecorder record.EventRecorder
	GVK           schema.GroupVersionKind

	releaseHook ReleaseHookFunc

	checkInterval      time.Duration
	updateInterval     time.Duration
	lastSucUpdateCheck time.Time
}

func NewReconcileAmbassadorInstallation(mgr manager.Manager) *ReconcileAmbassadorInstallation {
	checkInterval := getEnvDuration(defaultCheckIntervalEnvVar, defaultCheckInterval)
	updateInterval := getEnvDuration(defaultUpdateIntervalEnvVar, defaultUpdateInterval)

	return &ReconcileAmbassadorInstallation{
		Manager:            mgr,
		Client:             mgr.GetClient(),
		Scheme:             mgr.GetScheme(),
		EventRecorder:      mgr.GetEventRecorderFor(defControllerName),
		GVK:                DefaultGVK,
		checkInterval:      checkInterval,
		updateInterval:     updateInterval,
		lastSucUpdateCheck: time.Time{},
	}
}

// Reconcile reads that state of the cluster for a AmbassadorInstallation object and makes changes based on the state read
// and what is in the AmbassadorInstallation.Spec
// Note:
// The Controller will requeue the Request to be processed again if the returned error is non-nil or
// Result.Requeue is true, otherwise upon completion it will remove the work from the queue.
func (r *ReconcileAmbassadorInstallation) Reconcile(request reconcile.Request) (reconcile.Result, error) {
	reqLogger := log.WithValues("Request.Namespace", request.Namespace, "Request.Name", request.Name)
	reqLogger.Info("Reconciling AmbassadorInstallation")

	ambInstName := types.NamespacedName{Name: request.Name, Namespace: request.Namespace}
	ambIns, err := r.lookupAmbInst(ambInstName)
	if err != nil {
		log.Error(err, "Failed to lookup resource")
		return reconcile.Result{}, err
	}

	// This is only going to happen when we could not find the AmbassadorInstallation resource
	if ambIns == nil {
		return reconcile.Result{}, nil
	}

	deleted := ambIns.GetDeletionTimestamp() != nil
	pendingFinalizers := ambIns.GetFinalizers()

	// get some values we want to override from the CR
	// check the values we can set in https://github.com/datawire/ambassador-chart/#configuration
	ambObj, err := unsToAmbIns(ambIns)
	if err != nil {
		return reconcile.Result{}, err
	}

	status := ambassador.StatusFor(ambIns)

	// check if this AmbassadorInstallation was marked as a Duplicate in the past
	lastDuplicateCondition := ambObj.Status.LastCondition(ambassador.AmbInsCondition{Reason: ambassador.ReasonDuplicateError})
	if lastDuplicateCondition.Reason == ambassador.ReasonDuplicateError {
		reqLogger.Info("AmbassadorInstallation marked as duplicate: ignored")
		return reconcile.Result{}, nil
	}

	// check if this is the first and only AmbassadorInstallation in this namespace
	// if it is not, mark the status as Duplicate
	isFirstAmbIns, err := r.isFirstAmbInst(ambIns)
	if err != nil {
		return reconcile.Result{}, err
	}
	if !isFirstAmbIns {
		status.SetCondition(ambassador.AmbInsCondition{
			Type:    ambassador.ConditionIrreconcilable,
			Status:  ambassador.StatusFalse,
			Reason:  ambassador.ReasonDuplicateError,
			Message: fmt.Sprintf("There is a previous AmbassadorInstallation in this namespace. Disabling this one."),
		})
		return reconcile.Result{}, r.updateResourceStatus(ambIns, status)
	}

	// check if there are finalizers installed for this instance: if not, install
	// our finalizer.
	if !deleted && !contains(pendingFinalizers, defFinalizerID) {
		log.V(1).Info("Adding finalizer", "ID", defFinalizerID)
		finalizers := append(pendingFinalizers, defFinalizerID)
		ambIns.SetFinalizers(finalizers)

		err = r.Client.Update(context.TODO(), ambIns)

		// Need to requeue because finalizer update does not change metadata.generation
		return reconcile.Result{Requeue: true}, err
	}

	status.SetCondition(ambassador.AmbInsCondition{
		Type:   ambassador.ConditionInitialized,
		Status: ambassador.StatusTrue,
	})
	status.RemoveCondition(ambassador.ConditionIrreconcilable)

	// copy all the values, both from the default values as from the user provided ones
	helmValues := HelmValues{}
	for k, v := range defaultChartValues {
		helmValues[k] = v
	}
	for _, f := range defExtraValuesFiles {
		log.Info("Trying to load values from file", "file", f)
		values, err := readValuesFile(f)
		if err != nil {
			log.Info("Error when loading file", "file", f, "error", err)
			continue
		}
		for k, v := range values {
			log.Info("Settings value from file", "file", f, "var", k, "value", v)
			helmValues[k] = v
		}
	}
	if len(ambObj.Spec.HelmValues) > 0 {
		log.Info("Settings value from AmbassadorInstallation")
		for k, v := range ambObj.Spec.HelmValues {
			log.V(1).Info("Settings value from AmbassadorInstallation", "var", k, "value", v)
			helmValues[k] = v
		}
	}

	// `enableAES: true` means `installOSS: false`
	// `enableAES: false` means `installOSS: true`
	// Throw an error if these fields are inconsistent with each other
	if (ambObj.Spec.HelmValues["enableAES"] == "false" && ambObj.Spec.InstallOSS == false) ||
		(ambObj.Spec.HelmValues["enableAES"] == "true" && ambObj.Spec.InstallOSS == true) {
		log.Info("helmValues.enableAES and installOSS fields conflict with each other",
			"enableAES", ambObj.Spec.HelmValues["enableAES"], "installOSS", ambObj.Spec.InstallOSS)
		return reconcile.Result{}, fmt.Errorf("helmValues.enableAES and installOSS fields conflict with each other")
	}

	if len(ambObj.Spec.BaseImage) > 0 {
		repo, tag, err := parseRepoTag(ambObj.Spec.BaseImage)
		if err != nil {
			status.SetCondition(ambassador.AmbInsCondition{
				Type:    ambassador.ConditionReleaseFailed,
				Status:  ambassador.StatusTrue,
				Reason:  ambassador.ReasonParametersError,
				Message: fmt.Sprintf("could not parse base image from %s", ambObj.Spec.BaseImage),
			})
			_ = r.updateResourceStatus(ambIns, status)
			return reconcile.Result{}, err
		}
		reqLogger.Info("Using custom base image", "repo", repo, "tag", tag)
		helmValues["image.repository"] = repo
		helmValues["image.tag"] = tag
	}

	if ambObj.Spec.InstallOSS {
		helmValues["enableAES"] = "false"
		// We do not want to update image.repository and image.tag if they have already been populated by user supplied
		// configuration.
		if len(helmValues["image.repository"]) == 0 && len(helmValues["image.tag"]) == 0 {
			helmValues["image.repository"] = "quay.io/datawire/ambassador"
		}
	}

	if len(ambObj.Spec.LogLevel) > 0 {
		reqLogger.Info("Using custom log level", "level", ambObj.Spec.LogLevel)
		helmValues["pro.logLevel"] = ambObj.Spec.LogLevel
	}

	// create a new parsed checker for versions
	chartVersion, err := helm.NewChartVersionRule(ambObj.Spec.Version)
	if err != nil {
		message := fmt.Sprintf("could not parse version from %q", ambObj.Spec.Version)
		status.SetCondition(ambassador.AmbInsCondition{
			Type:    ambassador.ConditionReleaseFailed,
			Status:  ambassador.StatusTrue,
			Reason:  ambassador.ReasonParametersError,
			Message: message,
		})
		_ = r.updateResourceStatus(ambIns, status)
		return reconcile.Result{}, err
	}

	options := HelmManagerOptions{
		Manager: r.Manager,
		HelmDownloaderOptions: helm.HelmDownloaderOptions{
			URL:     ambObj.Spec.HelmRepo,
			Version: chartVersion,
		},
	}
	// create a new manager for the remote Helm repo URL
	chartsMgr, err := NewHelmManager(options, helmValues)
	if err != nil {
		return reconcile.Result{}, err
	}

	// check if this AmbassadorInstallation CR has been deleted.
	// in that case, Ambassador should be removed.
	if deleted {
		reqLogger.Info("AmbassadorInstallation deleted: uninstalling Ambassador")
		return r.deleteRelease(ambIns, pendingFinalizers, chartsMgr)
	}

	// get an update window from the arguments in the CRD
	window, err := NewUpdateWindow(ambObj.Spec.UpdateWindow)
	if err != nil {
		message := fmt.Sprintf("could not parse an update window from %s", ambObj.Spec.UpdateWindow)
		reqLogger.Info(message)

		status.SetCondition(ambassador.AmbInsCondition{
			Type:    ambassador.ConditionReleaseFailed,
			Status:  ambassador.StatusTrue,
			Reason:  ambassador.ReasonParametersError,
			Message: message,
		})
		_ = r.updateResourceStatus(ambIns, status)
		return reconcile.Result{}, err
	}

	return r.tryInstallOrUpdate(ambIns, chartsMgr, window)
}

func (r *ReconcileAmbassadorInstallation) updateResource(o runtime.Object) error {
	return r.Client.Update(context.TODO(), o)
}

func (r *ReconcileAmbassadorInstallation) updateResourceStatus(o *unstructured.Unstructured, status *ambassador.AmbassadorInstallationStatus) error {
	o.Object["status"] = status
	return r.Client.Status().Update(context.TODO(), o)
}
