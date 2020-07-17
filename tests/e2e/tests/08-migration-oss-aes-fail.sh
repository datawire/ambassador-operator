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
IMAGE_REPOSITORY="${OFFICIAL_REGISTRY}/ambassador"
AES_IMAGE_REPOSITORY="${OFFICIAL_REGISTRY}/aes"

########################################################################################################################

[ -z "$DEV_REGISTRY" ] && abort "no DEV_REGISTRY defined"
[ -z "$KUBECONFIG" ] && abort "no KUBECONFIG defined"

########################################################################################################################

info "Installing the Operator..."
oper_install "yaml" "$TEST_NAMESPACE" || failed "could not deploy operator"
oper_wait_install -n "$TEST_NAMESPACE" || failed "the Ambassador operator is not alive"

info "Installing Ambassador..."

info "Creating AmbassadorInstallation with 'installOSS: true'..."
apply_amb_inst_oss -n "$TEST_NAMESPACE"
info "AmbassadorInstallation created successfully..."

oper_wait_install_amb -n "$TEST_NAMESPACE" || abort "the Operator did not install Ambassador"

info "Checking the repository of Ambassador that has been deployed is $IMAGE_REPOSITORY..."
if ! amb_check_image_repository "$IMAGE_REPOSITORY" -n "$TEST_NAMESPACE"; then
	warn "Image not expected. Dumping Operator's logs:"
	oper_logs_dump -n "$TEST_NAMESPACE"
	failed "wrong version installed"
fi
passed "... good! Ambassador that has been deployed with $IMAGE_REPOSITORY"

info "Ambassador OSS should not install any AuthServices in namespace $TEST_NAMESPACE, checking..."
if ! kube_check_resource_empty "authservices" -n "$TEST_NAMESPACE"; then
	info "AuthServices are present in the namespace $TEST_NAMESPACE"
	kubectl get "authservices" -n "$TEST_NAMESPACE" -o yaml
	warn "Logs: Ambassador operator:"
	oper_logs_dump -n "$TEST_NAMESPACE"
	failed "OSS should not have AuthService installed in namespace $TEST_NAMESPACE"
fi
passed "... good! AuthServices are not present in the namespace $TEST_NAMESPACE"

amb_inst_check_success -n "$TEST_NAMESPACE" || {
	warn "Unexpected content in AmbassadorInstallation description:"
	amb_inst_describe -n "$TEST_NAMESPACE"
	warn "Logs: Ambassador operator:"
	oper_logs_dump -n "$TEST_NAMESPACE" failed "Success not found in AmbassadorInstallation description"
}

cat <<EOF | kubectl apply -n "$TEST_NAMESPACE" -f -
apiVersion: getambassador.io/v2
kind: AuthService
metadata:
  name: authentication
spec:
  timeout_ms: 5000
EOF

info "Updating AmbassadorInstallation with 'installOSS: false'..."
apply_amb_inst_aes -n "$TEST_NAMESPACE"
info "AmbassadorInstallation updated successfully..."

info "Waiting for Operator to trigger an update..."
sleep 5

i=0
timeout=$DEF_WAIT_TIMEOUT
until [ "$(kubectl get deployments "$AMB_DEPLOY" -n "$TEST_NAMESPACE" -o=jsonpath='{.status.updatedReplicas}')" -ne 3 ] || [ $i -ge $timeout ]; do
	info "Checking if AES is installed: $i"
	info "updatedReplicas $(kubectl get deployments "$AMB_DEPLOY" -n "$TEST_NAMESPACE" -o=jsonpath='{.status.updatedReplicas}'), required 3"
	i=$((i + 1))
	sleep 1
done

if [ $i -lt $timeout ]; then
	failed "AES should never get ready, but it got ready after $timeout seconds!"
fi
passed "AES never got ready because AuthService was installed before migration"

[ -n "$VERBOSE" ] && {
	info "Describe: AmbassadorInstallation:" && amb_inst_describe -n "$TEST_NAMESPACE"
	info "Logs: Ambassador operator" && oper_logs_dump -n "$TEST_NAMESPACE"
}

exit 0
