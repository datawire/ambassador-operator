#!/usr/bin/env bash

kind_sh_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$kind_sh_dir" ] || {
	echo "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}

TOP_DIR="$kind_sh_dir/../.."

source "$TOP_DIR/ci/common.sh"

CLUSTER_PROVIDERS=${CLUSTER_PROVIDERS:-$TOP_DIR/ci/cluster-providers}
[ -d $CLUSTER_PROVIDERS ] || abort "FATAL: no cluster providers in $CLUSTER_PROVIDERS"

# shellcheck source=../../ci/cluster-providers/providers.sh
source "$CLUSTER_PROVIDERS/providers.sh"

########################################################################################################################

MANIF_URL="https://github.com/datawire/ambassador-operator/releases/latest/download/ambassador-operator-kind.yaml"

CRD_URL="https://github.com/datawire/ambassador-operator/releases/latest/download/ambassador-operator-crds.yaml"

# run verbose
VERBOSE=${VERBOSE:-}

# ports for listening in KIND (the cluster provider will use them)
KIND_HTTP_PORT=${KIND_HTTP_PORT:-$((30180 + RANDOM % 100))}
KIND_HTTPS_PORT=${KIND_HTTPS_PORT:-$((30443 + RANDOM % 100))}
export KIND_HTTP_PORT KIND_HTTPS_PORT

# these tests do not need a registry
KIND_REGISTRY_ENABLED=
export KIND_REGISTRY_ENABLED

########################################################################################################################
# main
########################################################################################################################

export VERBOSE

info "Running test for KIND..."

info "Starting KIND cluster..."
cleanup() {
	cluster_provider 'delete'
	cluster_provider 'delete-registry'
}
trap cleanup EXIT

cluster_provider 'create' || abort "no cluster created"
passed "cluster created"

eval "$(cluster_provider 'get-env')"

info "Applying CRDs from $CRD_URL"
kubectl apply --kubeconfig="$DEV_KUBECONFIG" -f $CRD_URL || abort "when loading the CRDs"
passed "CRDs loaded"

info "Installing from $MANIF_URL and waiting for the Operator"
kubectl apply --kubeconfig="$DEV_KUBECONFIG" -n ambassador -f $MANIF_URL || abort "when loading for the Operator"
kubectl wait --kubeconfig="$DEV_KUBECONFIG" --timeout=180s -n ambassador --for=condition=deployed ambassadorinstallations/ambassador ||
	abort "when waiting for the Operator"
passed "Operator ready"

info "Loading an example..."
kubectl apply --kubeconfig="$DEV_KUBECONFIG" -f https://kind.sigs.k8s.io/examples/ingress/usage.yaml || abort "when loading the example"
passed "example loaded"

info "Annotating Ingress..."
kubectl --kubeconfig="$DEV_KUBECONFIG" annotate ingress example-ingress kubernetes.io/ingress.class=ambassador || abort "when annotating ingress"
passed "Ingress annotated"

info "Wait for URLs..."
wait_url localhost:$KIND_HTTP_PORT/foo || abort "while waiting for localhost/foo"
wait_url localhost:$KIND_HTTP_PORT/bar || abort "while waiting for localhost/bar"
passed "URLs are responding: everything looks good!"
