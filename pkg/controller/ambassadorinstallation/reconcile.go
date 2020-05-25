package ambassadorinstallation

import (
	"context"
	"fmt"
	"time"

	"github.com/datawire/ambassador/pkg/helm"

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

	// OSS flavor to set in DeployedRelease.flavor
	flavorOSS = "OSS"

	// AES flavor to set in DeployedRelease.flavor
	flavorAES = "AES"
)

var (
	// some default Helm values
	defaultChartValues = HelmValues{
		"deploymentTool": "amb-oper",
	}

	// default image used for the OSS version
	defOSSImageRepository = fmt.Sprintf("%s/ambassador", DefRegistry)

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
	Client             client.Client
	Scheme             *runtime.Scheme
	Manager            manager.Manager
	EventRecorder      record.EventRecorder
	GVK                schema.GroupVersionKind
	Scout              *Scout
	releaseHook        ReleaseHookFunc
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
		Scout:              nil,
	}
}

// Reconcile reads that state of the cluster for a AmbassadorInstallation object and makes changes based on the state read
// and what is in the AmbassadorInstallation.Spec
// Note:
// The Controller will requeue the Request to be processed again if the returned error is non-nil or
// Result.Requeue is true, otherwise upon completion it will remove the work from the queue.
func (r *ReconcileAmbassadorInstallation) Reconcile(request reconcile.Request) (reconcile.Result, error) {
	reqLogger := log.WithValues("Request.Namespace", request.Namespace, "Request.Name", request.Name)

	// ...and log it.
	reqLogger.Info("Reconciling AmbassadorInstallation")

	ambInstName := types.NamespacedName{Name: request.Name, Namespace: request.Namespace}
	ambIns, err := r.lookupAmbInst(ambInstName)

	if err != nil {
		log.Info("Failed to lookup resource")
		return reconcile.Result{}, err
	}

	// Reset the report index and initialize the Reporter.  No calls
	// to r.ReportEvent, r.ReportError are allowed before this point.
	r.BeginReporting("reconcile", ambIns.GetUID())

	// Report beginning the reconciliation process to Metriton
	r.ReportEvent("start_reconciliation")

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

	spec := ambObj.Spec
	status := ambassador.StatusFor(ambIns)
	specHelmValues := GetHelmValuesAmbIns(ambIns) // values passes in the spec: just for reading

	// check if this AmbassadorInstallation was marked as a Duplicate in the past
	lastDuplicateCondition := status.LastCondition(ambassador.AmbInsCondition{Reason: ambassador.ReasonDuplicateError})
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
		message := fmt.Sprintf("There is a previous AmbassadorInstallation in this namespace. Disabling this one.")

		// Report to Metriton
		r.ReportEvent("disabling_previous_installation", ScoutMeta{"message", message})

		status.SetCondition(ambassador.AmbInsCondition{
			Type:    ambassador.ConditionIrreconcilable,
			Status:  ambassador.StatusFalse,
			Reason:  ambassador.ReasonDuplicateError,
			Message: message,
		})

		return reconcile.Result{}, r.updateResourceStatus(ambIns, status)
	}

	// check if there are finalizers installed for this instance: if not, install our finalizer.
	if !deleted && !contains(pendingFinalizers, defFinalizerID) {
		log.V(1).Info("Adding finalizer", "ID", defFinalizerID)
		finalizers := append(pendingFinalizers, defFinalizerID)
		ambIns.SetFinalizers(finalizers)

		err = r.Client.Update(context.TODO(), ambIns)

		// Need to requeue because finalizer update does not change metadata.generation
		return reconcile.Result{Requeue: true}, err
	}

	// Condition initialized
	r.ReportEvent("condition_initialized")

	status.SetCondition(ambassador.AmbInsCondition{
		Type:   ambassador.ConditionInitialized,
		Status: ambassador.StatusTrue,
	})

	status.RemoveCondition(ambassador.ConditionIrreconcilable)

	// process all static Helm values: the default ones, the ones coming from files, etc...
	helmValues := HelmValues{}
	helmValues.AppendFrom(defaultChartValues, true) // copy the default values

	for _, f := range defExtraValuesFiles {
		log.Info("Trying to load values from file", "file", f)
		values, err := readValuesFile(f)
		if err != nil {
			log.Info("Error when loading file", "file", f, "error", err)
			continue
		}
		helmValues.AppendFrom(values, true)
	}
	if err := helmValues.WriteToAmbIns(ambIns, false); err != nil {
		reqLogger.Info("Internal error when adding static helm values: %v", err)
		return reconcile.Result{}, err
	}

	// `enableAES: true` means `installOSS: false`
	// `enableAES: false` means `installOSS: true`
	// Throw an error if these fields are inconsistent with each other
	enableOSS := spec.InstallOSS
	if enableAESUntyped, ok := specHelmValues["enableAES"]; ok {
		if enableAES, ok := enableAESUntyped.(bool); ok {
			if (!enableAES && !enableOSS) || (enableAES && enableOSS) {
				message := "helmValues.enableAES and installOSS fields conflict with each other"

				log.Info(message, "enableAES", enableAES, "installOSS", enableOSS)

				// Report to Metriton
				r.ReportEvent("fail_helm_values_conflict",
					ScoutMeta{"message", message},
					ScoutMeta{"error", 0},
					ScoutMeta{"enableAES", enableAES},
					ScoutMeta{"installOSS", enableOSS})

				status.SetCondition(ambassador.AmbInsCondition{
					Type:    ambassador.ConditionReleaseFailed,
					Status:  ambassador.StatusTrue,
					Reason:  ambassador.ReasonParametersError,
					Message: message,
				})

				_ = r.updateResourceStatus(ambIns, status)
				return reconcile.Result{}, fmt.Errorf(message)
			}
		}
	}

	helmValuesStrings := HelmValuesStrings{} // high-precedence values: they will override any other values

	if len(spec.BaseImage) > 0 {
		repo, tag, err := parseRepoTag(spec.BaseImage)
		if err != nil {
			message := fmt.Sprintf("could not parse base image from %s", spec.BaseImage)

			// Report to Metriton
			r.ReportError("fail_parse_image", message, err)

			status.SetCondition(ambassador.AmbInsCondition{
				Type:    ambassador.ConditionReleaseFailed,
				Status:  ambassador.StatusTrue,
				Reason:  ambassador.ReasonParametersError,
				Message: message,
			})

			_ = r.updateResourceStatus(ambIns, status)
			return reconcile.Result{}, err
		}
		reqLogger.Info("Using custom base image", "repo", repo, "tag", tag)
		helmValuesStrings["image.repository"] = repo
		helmValuesStrings["image.tag"] = tag
	}

	flavor := ""
	isMigrating := false

	if enableOSS {
		// Check user is not trying to migrate from AES to OSS...
		if status.DeployedRelease != nil {
			if status.DeployedRelease.Flavor != flavorOSS {
				err = fmt.Errorf("migration from AES to OSS not supported")
				log.Error(err, "")
				return reconcile.Result{}, err
			}
		}

		// This is a huge HACK! The line below should have been -
		// helmValues["enableAES"] = false
		// but NewHelmManager and its guts only accept map[string]string which is wrong, because not all Helm values
		// are map[string]string.
		// However, we found out that all objects in ambObj["spec"] are passed to Helm by NewManager, so that is what
		// this code is doing.
		reqLogger.Info("AES: disabled")
		err := unstructured.SetNestedField(ambIns.Object, false, "spec", "enableAES")
		if err != nil {
			message := "could not set spec.enableAES"
			r.ReportError("fail_set_spec", message, err)
			reqLogger.Error(err, message)
		}

		// We do not want to update image.repository and image.tag if they have already been populated by user supplied
		// configuration.
		if len(helmValuesStrings["image.repository"]) == 0 && len(helmValuesStrings["image.tag"]) == 0 {
			reqLogger.Info("Setting image to OSS", "image", defOSSImageRepository)
			helmValuesStrings["image.repository"] = defOSSImageRepository
		}

		flavor = flavorOSS
		reqLogger.Info("Flavor: OSS")

	} else {
		if status.DeployedRelease != nil {
			if status.DeployedRelease.Flavor != flavorAES {
				log.Info("Upgrading the cluster from OSS to AES...")

				// if AES is already installed, then we don't need to look for AuthService or RateLimitService
				log.Info("Checking that AuthService/RateLimitService do not exist in the cluster.")

				log.Info("Checking for AuthService...")
				authServiceList, err := r.lookupResourceList(&schema.GroupVersionKind{
					Group:   "getambassador.io",
					Version: "v2",
					Kind:    "AuthService",
				}, request.Namespace)

				if err != nil {
					message := "could not look up AuthService in the cluster"
					err = fmt.Errorf(message)
					log.Error(err, "")

					status.SetCondition(ambassador.AmbInsCondition{
						Type:    ambassador.ConditionReleaseFailed,
						Status:  ambassador.StatusTrue,
						Reason:  ambassador.ReasonUpgradePrecondError,
						Message: message,
					})
					_ = r.updateResourceStatus(ambIns, status)
					r.ReportError("fail_no_authservice", message, err)
					return reconcile.Result{RequeueAfter: r.checkInterval}, err
				}

				if len(authServiceList.Items) > 0 {
					message := "AuthService(s) exist in the cluster, please remove to upgrade to AES"
					err = fmt.Errorf(message)
					log.Error(err, "")

					status.SetCondition(ambassador.AmbInsCondition{
						Type:    ambassador.ConditionReleaseFailed,
						Status:  ambassador.StatusTrue,
						Reason:  ambassador.ReasonUpgradePrecondError,
						Message: message,
					})
					_ = r.updateResourceStatus(ambIns, status)
					r.ReportError("fail_existing_authservice", message, err)
					return reconcile.Result{RequeueAfter: r.checkInterval}, err
				}

				log.Info("Checking for RateLimitService...")
				rateLimitServiceList, err := r.lookupResourceList(&schema.GroupVersionKind{
					Group:   "getambassador.io",
					Version: "v2",
					Kind:    "RateLimitService",
				}, request.Namespace)

				if err != nil {
					message := "could not look up RateLimitService in the cluster"
					err = fmt.Errorf(message)
					log.Error(err, "")

					status.SetCondition(ambassador.AmbInsCondition{
						Type:    ambassador.ConditionReleaseFailed,
						Status:  ambassador.StatusTrue,
						Reason:  ambassador.ReasonUpgradePrecondError,
						Message: message,
					})
					_ = r.updateResourceStatus(ambIns, status)
					r.ReportError("fail_no_ratelimitservice", message, err)
					return reconcile.Result{RequeueAfter: r.checkInterval}, err
				}

				if len(rateLimitServiceList.Items) > 0 {
					message := "RateLimitService(s) exist in the cluster, please remove to upgrade to AES"
					err = fmt.Errorf(message)
					log.Error(err, "")

					status.SetCondition(ambassador.AmbInsCondition{
						Type:    ambassador.ConditionReleaseFailed,
						Status:  ambassador.StatusTrue,
						Reason:  ambassador.ReasonUpgradePrecondError,
						Message: message,
					})
					_ = r.updateResourceStatus(ambIns, status)
					r.ReportError("fail_existing_ratelimitservice", message, err)
					return reconcile.Result{RequeueAfter: r.checkInterval}, err
				}

				isMigrating = true
			}
		}

		flavor = flavorAES
		reqLogger.Info("Flavor: AES")
	}

	if len(spec.LogLevel) > 0 {
		reqLogger.Info("Using custom log level", "level", spec.LogLevel)
		helmValuesStrings["pro.logLevel"] = spec.LogLevel
	}

	// create a new parsed checker for versions
	chartVersion, err := helm.NewChartVersionRule(spec.Version)
	if err != nil {
		message := fmt.Sprintf("could not parse version from %q", spec.Version)

		// Report to Metriton
		r.ReportError("fail_parse_chart_version", message, err)

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
			URL:     spec.HelmRepo,
			Version: chartVersion,
		},
	}
	// create a new manager for the remote Helm repo URL
	chartsMgr, err := NewHelmManager(options, helmValuesStrings)
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
	window, err := NewUpdateWindow(spec.UpdateWindow)
	if err != nil {
		message := fmt.Sprintf("could not parse an update window from %s", spec.UpdateWindow)

		// Report to Metriton
		r.ReportError("fail_parse_update_window", message, err)

		// ...and log the error as well.
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

	r.ReportEvent("completed_reconciliation")
	return r.tryInstallOrUpdate(ambIns, chartsMgr, window, isMigrating, flavor)
}

func (r *ReconcileAmbassadorInstallation) updateResource(o runtime.Object) error {
	return r.Client.Update(context.TODO(), o)
}

func (r *ReconcileAmbassadorInstallation) updateResourceStatus(o *unstructured.Unstructured, status *ambassador.AmbassadorInstallationStatus) error {
	o.Object["status"] = status
	return r.Client.Status().Update(context.TODO(), o)
}

// Initialize the Scout instance and reset.
func (r *ReconcileAmbassadorInstallation) BeginReporting(mode string, installID types.UID) {
	r.Scout = NewScout(mode, installID)
	r.Scout.Reset()
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
