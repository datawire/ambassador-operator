#!/bin/bash

this_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$this_dir" ] || {
	echo "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}
TOP_DIR=$(realpath $this_dir/../../..)

# shellcheck source=../common.sh
source "$this_dir/../common.sh"

########################################################################################################################
# local variables
########################################################################################################################

# the versions of Ambassador to install
AMB_VERSION="1.4.1"

# `image.tag` that will be forced in a helmvalue
AMB_IMAGE_TAG="1.4.0"

########################################################################################################################

[ -z "$DEV_REGISTRY" ] && abort "no DEV_REGISTRY defined"
[ -z "$KUBECONFIG" ] && abort "no KUBECONFIG defined"

########################################################################################################################

pushd "$TOP_DIR" >/dev/null || exit 1

info "Installing the Operator..."
oper_install "yaml" "$TEST_NAMESPACE" || failed "could not deploy operator"
oper_wait_install -n "$TEST_NAMESPACE" || failed "the Ambassador operator is not alive"

info "Installing Ambassador with some values..."
# see https://github.com/datawire/ambassador-chart#configuration for values
cat <<EOF | kubectl apply -n "$TEST_NAMESPACE" -f -
apiVersion: getambassador.io/v2
kind: AmbassadorInstallation
metadata:
  name: ${AMB_INSTALLATION_NAME}
spec:
  version: "*"
  logLevel: info
  helmValues:
    namespace:
      name: ${TEST_NAMESPACE}
    image:
      pullPolicy: Always
    image.tag: ${AMB_IMAGE_TAG}
    service.ports[0].name: http
    service.ports[0].port: 80
    service.ports[0].targetPort: 8080
EOF

info "Waiting for the Operator to install Ambassador"
if ! wait_amb_addr -n "$TEST_NAMESPACE"; then
	warn "It seems Ambassador was not installed:"
	kubectl get deplokments -n $TEST_NAMESPACE
	warn "Dumping Operator's logs:"
	oper_logs_dump -n "$TEST_NAMESPACE"
	failed "timeout while waiting for an Ambassador IP"
fi
passed "... good! Ambassador has been installed by the Operator!"

info "Checking Ambassador values:"
values="$(helm get values -n "$TEST_NAMESPACE" ${AMB_INSTALLATION_NAME})"
echo "$values"

echo "$values" | grep -q "name: $TEST_NAMESPACE" || abort "no namespace found in values"
echo "$values" | grep -q "name: http" || abort "no http port found in values"

info "Checking the version of Ambassador that has been deployed is $AMB_IMAGE_TAG..."
if ! amb_check_image_tag "$AMB_IMAGE_TAG" -n "$TEST_NAMESPACE"; then
	oper_logs_dump -n "$TEST_NAMESPACE"
	failed "wrong version installed"
fi
passed "... good! The version is $AMB_VERSION_FIRST"

exit 0
