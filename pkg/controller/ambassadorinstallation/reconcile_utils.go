package ambassadorinstallation

import (
	"context"
	"sort"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"

	ambassador "github.com/datawire/ambassador-operator/pkg/apis/getambassador/v2"
)

// lookupAmbInst looks for a AmbassadorInstallation instance with the namespace/name/gvk
func (r *ReconcileAmbassadorInstallation) lookupAmbInst(n types.NamespacedName) (*unstructured.Unstructured, error) {
	o := &unstructured.Unstructured{}
	o.SetGroupVersionKind(r.GVK)
	o.SetNamespace(n.Namespace)
	o.SetName(n.Name)

	log := log.WithValues(
		"namespace", o.GetNamespace(),
		"name", o.GetName(),
		"apiVersion", o.GetAPIVersion(),
		"kind", o.GetKind(),
	)
	//

	log.V(3).Info("Fetching the AmbassadorInstallation instance")
	err := r.Client.Get(context.TODO(), n, o)
	if apierrors.IsNotFound(err) {
		return nil, nil
	}
	if err != nil {
		log.Error(err, "Failed to find resource")
		return nil, err
	}

	return o, nil
}

// listAmbInst checks if the AmbassadorInstallations instance is the first one in the namespace
func (r *ReconcileAmbassadorInstallation) isFirstAmbInst(ambInst *unstructured.Unstructured) (bool, error) {
	log.V(1).Info("Reconciling")

	listOpt := client.ListOptions{
		Namespace: ambInst.GetNamespace(),
	}

	log.V(3).Info("Getting list of AmbassadorInstallations")
	lst := ambassador.AmbassadorInstallationList{}
	err := r.Client.List(context.TODO(), &lst, &listOpt)
	if apierrors.IsNotFound(err) {
		log.Error(err, "No resources found",
			"gkv", r.GVK.String(), "namespace", ambInst.GetNamespace())
		return false, nil
	}
	if err != nil {
		log.Error(err, "Failed to list resources",
			"gkv", r.GVK.String(), "namespace", ambInst.GetNamespace())
		return false, err
	}

	installations := lst.Items
	sort.Slice(installations, func(i, j int) bool {
		return installations[i].CreationTimestamp.Before(&installations[j].CreationTimestamp)
	})

	return ambInst.GetCreationTimestamp() == installations[0].CreationTimestamp, nil
}

// unsToAmbIns returns an AmbassadorInstallation from a unstructured.Unstructured
func unsToAmbIns(o *unstructured.Unstructured) (*ambassador.AmbassadorInstallation, error) {
	uns := o.UnstructuredContent()

	// convert unstructured.Unstructured to a AmbassadorInstallation
	var ambInstallation *ambassador.AmbassadorInstallation
	if err := runtime.DefaultUnstructuredConverter.FromUnstructured(uns, &ambInstallation); err != nil {
		return nil, err
	}

	return ambInstallation, nil
}
