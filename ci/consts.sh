#!/bin/bash

consts_sh_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$consts_sh_dir" ] || {
	echo "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}
TOP_DIR=$(realpath $consts_sh_dir/..)

########################################################################################################################
# constants
########################################################################################################################

# default time to wait
DEF_WAIT_TIMEOUT=100

# the cluster provider. by default use the dummy provider (uses the current kubeconfig)
CLUSTER_PROVIDER="${CLUSTER_PROVIDER:-}"
DEF_CLUSTER_PROVIDER="dummy"

# default cluster machine name
DEF_CLUSTER_MACHINE="default"

# the kubeconfig, and possible kubeconfig files, and the default one
DEV_KUBECONFIG="${DEV_KUBECONFIG:-}"
DEF_KUBECONFIG="${HOME}/.kube/config"

# the registry. by default, a local one.
DEV_REGISTRY="${DEV_REGISTRY:-}"
DEF_REGISTRY="registry.local:5000"

# the external address (ie, IP or hostname) where the Ambassador service will be alive
# this AMB_EXT_ADDR will also be sued as the Hostanem for certificates, so make sure it is
# reachable by ACME
AMB_EXT_ADDR=""
DEF_AMB_EXT_ADDR="localhost"

# the namespace
AMB_NAMESPACE="ambassador"

# the name of the Ambassador deployment
AMB_DEPLOY="ambassador"

# the name of the ambassador operator deployment
AMB_OPER_DEPLOY="ambassador-operator"

# the CRDs
CRDS="$TOP_DIR/deploy/crds/getambassador.io_ambassadorinstallations_crd.yaml"

# the default image name
AMB_OPER_IMAGE_NAME="ambassador-operator"

# the default image tag
AMB_OPER_IMAGE_TAG="dev"

# a selector for detecting ambassador pods
AMB_POD_SELECTOR="-l app.kubernetes.io/name=ambassador"

# update and check intervals for the operator
# we don't need to use short intervals here
AMB_OPER_UPDATE_INTERVAL="5s"
AMB_OPER_CHECK_INTERVAL="5s"

# the name of the `AmbassadorInstallation` we will always create in tests, benchmarks, etc
AMB_INSTALLATION_NAME="ambassador"

########################################################################################################################
# tools
########################################################################################################################

# some kubectl arguments: apply
KUBECTL_APPLY_ARGS="--wait=true"

# some kubectl arguments: delete
KUBECTL_DELETE_ARGS="--wait=true --timeout=60s --ignore-not-found=true"

########################################################################################################################
# extra
########################################################################################################################

RED='\033[1;31m'
GRN='\033[1;32m'
YEL='\033[1;33m'
BLU='\033[1;34m'
WHT='\033[1;37m'
MGT='\033[1;95m'
CYA='\033[1;96m'
END='\033[0m'
BLOCK='\033[1;47m'

########################################################################################################################
# tools
########################################################################################################################

# some executables
EXE_SIEGE="siege"
EXE_KUBECTL=${KUBECTL:-$HOME/bin/kubectl}
EXE_KUBERNAUT=${KUBERNAUT:-$HOME/bin/kubernaut}
EXE_EDGECTL=${EDGECTL:-$HOME/bin/edgectl}
EXE_OSDK=${OSDK:-$HOME/bin/operator-sdk}
EXE_SHFMT=${SHFMT:-$HOME/bin/shfmt}
EXE_HELM=${HELM:-$HOME/bin/helm}

# some versions
KUBECTL_VERSION="1.15.3"
KUBERNAUT_VERSION="2018.10.24-d46c1f1"
OPERATOR_SDK_VERSION="v0.15.1"
GOLINT_VERSION="latest"

# the URLs where some EXEs are available
EXE_KUBECTL_URL="https://storage.googleapis.com/kubernetes-release/release/v${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
EXE_KUBERNAUT_URL="http://releases.datawire.io/kubernaut/${KUBERNAUT_VERSION}/linux/amd64/kubernaut"
EXE_EDGECTL_URL="https://metriton.datawire.io/downloads/linux/edgectl"
EXE_OSDK_URL="https://github.com/operator-framework/operator-sdk/releases/download/${OPERATOR_SDK_VERSION}/operator-sdk-${OPERATOR_SDK_VERSION}-x86_64-linux-gnu"
EXE_GOLINT_URL="https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh"
EXE_SHFMT_URL="https://github.com/mvdan/sh/releases/download/v2.6.4/shfmt_v2.6.4_linux_amd64"
HELM_TAR_URL="https://get.helm.sh/helm-v3.0.3-linux-amd64.tar.gz"

GEN_CRD_DOCS_URL="https://github.com/inercia/gen-crd-api-reference-docs/archive/master.zip"
