#!/usr/bin/env bash

minikube_sh_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$minikube_sh_dir" ] || {
	echo "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}

TOP_DIR="$minikube_sh_dir/../.."

source "$TOP_DIR/ci/common.sh"

########################################################################################################################

VERBOSE=${VERBOSE:-}

BIN_DIR=${BIN_DIR:-$HOME/bin}

MINIKUBE_EXE=${MINIKUBE_EXE:-$BIN_DIR/minikube}

MINIKUBE_URL="https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64"

########################################################################################################################

setup() {
    info "Installing minikube"
    curl -Lo ./minikube "$MINIKUBE_URL"
    chmod +x ./minikube
    mkdir -p "$(dirname "$MINIKUBE_EXE")"
	mv ./minikube "$MINIKUBE_EXE"
}

cleanup() {
	info "Deleting minikube cluster"

	[ -x "$MINIKUBE_EXE" ] || abort "no minikube executable at $MINIKUBE_EXE (env var MINIKUBE_EXE)"

	$MINIKUBE_EXE delete
}

run() {
    info "Running minikube smoke tests"

    [ -x "$MINIKUBE_EXE" ] || abort "no minikube executable at $MINIKUBE_EXE (env var MINIKUBE_EXE)"

    info "Starting a Kubernetes cluster with minikube (VM driver: none)"
    sudo "$MINIKUBE_EXE" start --vm-driver=none --profile=minikube || abort "error creating minikube cluster"
    "$MINIKUBE_EXE" update-context --profile=minikube
    passed "created minikube cluster"

    "$MINIKUBE_EXE" addons enable ambassador
    passed "enabled ambassador addon in minikube"

    kubectl wait --timeout=180s -n ambassador --for=condition=deployed ambassadorinstallations/ambassador ||
        abort "operator not ready"
    passed "operator ready"

    kubectl wait --timeout=180s -n ambassador --for=condition=available deployment/ambassador-operator ||
        abort "operator pods never came up"

    kubectl wait --timeout=180s -n ambassador --for=condition=available deployment/ambassador ||
        abort "ambassador pods never came up"
    passed "ambassador ready"

    info "Creating echoserver for ingress traffic"
    kubectl create deployment hello-minikube --image=k8s.gcr.io/echoserver:1.4
    wait_deploy "hello-minikube"

    kubectl expose deployment hello-minikube --port=8080

    cat <<EOF | kubectl apply -f - || abort "error creating ingress"
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: ambassador
  name: test-ingress
spec:
  rules:
  - http:
      paths:
      - path: /hello/
        backend:
          serviceName: hello-minikube
          servicePort: 8080
EOF
    passed "ingress created"

    kubectl port-forward service/ambassador -n ambassador 8080:80 &
    wait_url localhost:8080/hello/ || abort "did not get 200 OK from ingress endpoint"
    passed "got 200 OK from ingress endpoint, everything looks good!"
}

########################################################################################################################
# main
########################################################################################################################

read -r -d '' HELP_MSG <<EOF
minikube.sh [OPTIONS...] [COMMAND...]

where COMMAND can be:
  setup                     installs minikube
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
