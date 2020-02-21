package ambassadorinstallation

import (
	"bytes"
	"io"
	"reflect"
	"sync"

	"gopkg.in/yaml.v2"
	rpb "helm.sh/helm/v3/pkg/release"
	"k8s.io/apimachinery/pkg/api/meta"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/controller-runtime/pkg/controller"
	"sigs.k8s.io/controller-runtime/pkg/event"
	"sigs.k8s.io/controller-runtime/pkg/handler"
	crthandler "sigs.k8s.io/controller-runtime/pkg/handler"
	logf "sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/manager"
	crtpredicate "sigs.k8s.io/controller-runtime/pkg/predicate"
	"sigs.k8s.io/controller-runtime/pkg/source"

	ambassador "github.com/datawire/ambassador-operator/pkg/apis/getambassador/v2"
)

var log = logf.Log.WithName("controller-amb-inst")

var (
	// list of resources created when installing the Helm chart but
	// we are not really interested in. For example, we will create Secrets,
	// but we don't want to be invoked if those secrets change. For
	// other resources, it depends on how much we want to enforce the state...
	defaultIgnoredResources = map[string]struct{}{
		"AuthService":      {},
		"Deployment":       {},
		"Filter":           {},
		"FilterPolicy":     {},
		"Mapping":          {},
		"RateLimitService": {},
		"Secret":           {},
		"Service":          {},
		"ServiceAccount":   {},
	}
)

// Add creates a new AmbassadorInstallation Controller and adds it to the Manager. The Manager will set fields on the Controller
// and Start it when the Manager is Started.
func Add(mgr manager.Manager) error {
	return add(mgr, NewReconcileAmbassadorInstallation(mgr))
}

// add adds a new Controller to mgr with r as the reconcile.Reconciler
func add(mgr manager.Manager, r *ReconcileAmbassadorInstallation) error {
	// Create a new controller
	c, err := controller.New("ambassadorinstallation-controller", mgr, controller.Options{Reconciler: r})
	if err != nil {
		return err
	}

	// Watch for changes to primary resource AmbassadorInstallation
	err = c.Watch(&source.Kind{Type: &ambassador.AmbassadorInstallation{}}, &handler.EnqueueRequestForObject{})
	if err != nil {
		return err
	}

	// based on the code at https://github.com/operator-framework/operator-sdk/blob/master/pkg/helm/controller/controller.go#L93

	owner := &unstructured.Unstructured{}
	owner.SetGroupVersionKind(r.GVK)

	// using predefined functions for filtering events
	dependentPredicate := DependentPredicateFuncs()

	var m sync.RWMutex
	watches := map[schema.GroupVersionKind]struct{}{}
	releaseHook := func(release *rpb.Release) error {
		dec := yaml.NewDecoder(bytes.NewBufferString(release.Manifest))
		for {
			var u unstructured.Unstructured
			err := dec.Decode(&u.Object)
			if err == io.EOF {
				return nil
			}
			if err != nil {
				return err
			}

			gvk := u.GroupVersionKind()
			m.RLock()
			_, ok := watches[gvk]
			m.RUnlock()
			if ok {
				continue
			}

			restMapper := mgr.GetRESTMapper()
			depMapping, err := restMapper.RESTMapping(gvk.GroupKind(), gvk.Version)
			if err != nil {
				return err
			}
			ownerMapping, err := restMapper.RESTMapping(owner.GroupVersionKind().GroupKind(), owner.GroupVersionKind().Version)
			if err != nil {
				return err
			}

			depClusterScoped := depMapping.Scope.Name() == meta.RESTScopeNameRoot
			ownerClusterScoped := ownerMapping.Scope.Name() == meta.RESTScopeNameRoot

			if !ownerClusterScoped && depClusterScoped {
				m.Lock()
				watches[gvk] = struct{}{}
				m.Unlock()
				log.V(1).Info("Cannot watch cluster-scoped dependent resource for namespace-scoped owner. Changes to this dependent resource type will not be reconciled",
					"ownerApiVersion", r.GVK.GroupVersion(), "ownerKind", r.GVK.Kind, "apiVersion", gvk.GroupVersion(), "kind", gvk.Kind)
				continue
			}

			if _, ok := defaultIgnoredResources[gvk.Kind]; ok {
				log.V(1).Info("Will ignore changes in resource", "ownerApiVersion", r.GVK.GroupVersion(), "ownerKind", r.GVK.Kind, "apiVersion", gvk.GroupVersion(), "kind", gvk.Kind)
				continue
			}

			err = c.Watch(&source.Kind{Type: &u}, &crthandler.EnqueueRequestForOwner{OwnerType: owner}, dependentPredicate)
			if err != nil {
				return err
			}

			m.Lock()
			watches[gvk] = struct{}{}
			m.Unlock()
			log.V(1).Info("Watching dependent resource", "ownerApiVersion", r.GVK.GroupVersion(), "ownerKind", r.GVK.Kind, "apiVersion", gvk.GroupVersion(), "kind", gvk.Kind)
		}
	}
	r.releaseHook = releaseHook

	return nil
}

/////////////////////////////////////////////////////////////////////////////////////////

// DependentPredicateFuncs returns functions defined for filtering events
func DependentPredicateFuncs() crtpredicate.Funcs {

	dependentPredicate := crtpredicate.Funcs{
		// We don't need to reconcile dependent resource creation events
		// because dependent resources are only ever created during
		// reconciliation. Another reconcile would be redundant.
		CreateFunc: func(e event.CreateEvent) bool {
			o := e.Object.(*unstructured.Unstructured)
			log.V(1).Info("Skipping reconciliation for dependent resource creation", "name", o.GetName(), "namespace", o.GetNamespace(), "apiVersion", o.GroupVersionKind().GroupVersion(), "kind", o.GroupVersionKind().Kind)
			return false
		},

		// Reconcile when a dependent resource is deleted so that it can be
		// recreated.
		DeleteFunc: func(e event.DeleteEvent) bool {
			o := e.Object.(*unstructured.Unstructured)
			log.V(1).Info("Reconciling due to dependent resource deletion", "name", o.GetName(), "namespace", o.GetNamespace(), "apiVersion", o.GroupVersionKind().GroupVersion(), "kind", o.GroupVersionKind().Kind)
			return true
		},

		// Don't reconcile when a generic event is received for a dependent
		GenericFunc: func(e event.GenericEvent) bool {
			o := e.Object.(*unstructured.Unstructured)
			log.V(1).Info("Skipping reconcile due to generic event", "name", o.GetName(), "namespace", o.GetNamespace(), "apiVersion", o.GroupVersionKind().GroupVersion(), "kind", o.GroupVersionKind().Kind)
			return false
		},

		// Reconcile when a dependent resource is updated, so that it can
		// be patched back to the resource managed by the CR, if
		// necessary. Ignore updates that only change the status and
		// resourceVersion.
		UpdateFunc: func(e event.UpdateEvent) bool {
			old := e.ObjectOld.(*unstructured.Unstructured).DeepCopy()
			new := e.ObjectNew.(*unstructured.Unstructured).DeepCopy()

			delete(old.Object, "status")
			delete(new.Object, "status")
			old.SetResourceVersion("")
			new.SetResourceVersion("")

			if reflect.DeepEqual(old.Object, new.Object) {
				return false
			}
			log.V(1).Info("Reconciling due to dependent resource update", "name", new.GetName(), "namespace", new.GetNamespace(), "apiVersion", new.GroupVersionKind().GroupVersion(), "kind", new.GroupVersionKind().Kind)
			return true
		},
	}

	return dependentPredicate
}
