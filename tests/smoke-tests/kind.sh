#!/usr/bin/env bash

kind_sh_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$kind_sh_dir" ] || {
	echo "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}

TOP_DIR="$kind_sh_dir/../.."

source "$TOP_DIR/ci/common.sh"

#CLUSTER_PROVIDERS=${CLUSTER_PROVIDERS:-$TOP_DIR/ci/cluster-providers}
#[ -d $CLUSTER_PROVIDERS ] || {
#    echo "FATAL: no cluster providers in $CLUSTER_PROVIDERS"
#    exit 1
#}
## shellcheck source=../../ci/cluster-providers/providers.sh
#source "$CLUSTER_PROVIDERS/providers.sh"

########################################################################################################################

MANIF_URL="https://github.com/datawire/ambassador-operator/releases/latest/download/ambassador-operator-kind.yaml"

CRD_URL="https://github.com/datawire/ambassador-operator/releases/latest/download/ambassador-operator-crds.yaml"

########################################################################################################################

# run verbose
VERBOSE=${VERBOSE:-}

BIN_DIR=${BIN_DIR:-$HOME/bin}

KIND_EXE=${KIND_EXE:-$BIN_DIR/kind}

KIND_URL="https://github.com/kubernetes-sigs/kind/releases/latest/download/kind-linux-amd64"

########################################################################################################################
# setup dependencies
########################################################################################################################

setup() {
	info "Installing KIND"

	curl -Lo ./kind "$KIND_URL"
	chmod +x ./kind
	mkdir -p $(dirname $KIND_EXE)
	mv ./kind $KIND_EXE
}

cleanup() {
	info "Cleaning up things"

	[ -x $KIND_EXE ] || abort "no KIND executable at $KIND_EXE (env var KIND_EXE)"

	$KIND_EXE delete cluster
}

# run the same thing we explain in https://kind.sigs.k8s.io/docs/user/ingress/
run() {
	info "Running test for KIND..."

	[ -x $KIND_EXE ] || abort "no KIND executable at $KIND_EXE (env var KIND_EXE)"

	info "Creating cluster"
	cat <<EOF | $KIND_EXE create cluster --config=- || abort "when creating cluster"
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "ingress-ready=true"
  extraPortMappings:
  - containerPort: 80
    hostPort: 80
    protocol: TCP
  - containerPort: 443
    hostPort: 443
    protocol: TCP
EOF
	passed "cluster created"

	info "Applying CRDs from $CRD_URL"
	kubectl apply -f $CRD_URL || abort "when loading the CRDs"
	passed "CRDs loaded"

	info "Installing from $MANIF_URL and waiting for the Operator"
	kubectl apply -n ambassador -f $MANIF_URL || abort "when loading for the Operator"
	kubectl wait --timeout=180s -n ambassador --for=condition=deployed ambassadorinstallations/ambassador ||
		abort "when waiting for the Operator"
	passed "Operator ready"

	info "Loading an example..."
	kubectl apply -f https://kind.sigs.k8s.io/examples/ingress/usage.yaml || abort "when loading the example"
	passed "example loaded"

	info "Annotating Ingress..."
	kubectl annotate ingress example-ingress kubernetes.io/ingress.class=ambassador || abort "when annotating ingress"
	passed "Ingress annotated"

	info "Wait for URLs..."
	wait_url localhost/foo || abort "while waiting for localhost/foo"
	wait_url localhost/bar || abort "while waiting for localhost/bar"
	passed "URLs are responding: everything looks good!"
}

########################################################################################################################
# main
########################################################################################################################

read -r -d '' HELP_MSG <<EOF
kind.sh [OPTIONS...] [COMMAND...]

where COMMAND can be:
  setup                     installs KIND
  run                       runs the test
  cleanup                   cleanups stuff

EOF

export VERBOSE

if [[ $# -eq 0 ]]; then
	run
else
	opt=$1
	shift

	case "$opt" in
	setup)
		setup
		;;

	run)
		run
		;;

	cleanup)
		cleanup
		;;

	*)
		echo "$HELP_MSG"
		echo
		abort "Unknown command $opt"
		;;

	esac
fi
