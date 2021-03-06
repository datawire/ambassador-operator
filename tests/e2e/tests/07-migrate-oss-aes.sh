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

# a license for AES (it does not need to be valid)
AES_LICENSE_CONTENTS="this-is-a-license"

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

info "Adding a AES license..."
edgectl license -n "$TEST_NAMESPACE" $AES_LICENSE_CONTENTS

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

if [ $i -gt $timeout ]; then
	failed "Timeout waiting for AES to get installed after $timeout seconds!"
fi

passed "... good! The operator has updated Ambassador!"

info "Checking the repository of Ambassador that has been deployed is $AES_IMAGE_REPOSITORY..."
if ! amb_check_image_repository "$AES_IMAGE_REPOSITORY" -n "$TEST_NAMESPACE"; then
	warn "Image not expected. Dumping Operator's logs:"
	oper_logs_dump -n "$TEST_NAMESPACE"
	failed "wrong version installed"
fi
passed "... good! Ambassador has been deployed with $AES_IMAGE_REPOSITORY"

kubectl get -n "$TEST_NAMESPACE" AmbassadorInstallation

amb_inst_check_success -n "$TEST_NAMESPACE" || {
	warn "Success not found in AmbassadorInstallation:"
	amb_inst_describe -n "$TEST_NAMESPACE"
	failed "Success not found in AmbassadorInstallation description"
}

info "Checking the AES license..."
amb_license_data -n "$TEST_NAMESPACE" | grep -q "$AES_LICENSE_CONTENTS" || {
	warn "License not present or has changed:"
	amb_license_secret -n "$TEST_NAMESPACE"
	oper_logs_dump -n "$TEST_NAMESPACE"
	failed "License not present or has changed:"
}
passed "AES license contents ($AES_LICENSE_CONTENTS) have not changed."

[ -n "$VERBOSE" ] && {
	info "Describe: AmbassadorInstallation:" && amb_inst_describe -n "$TEST_NAMESPACE"
	info "Logs: Ambassador operator" && oper_logs_dump -n "$TEST_NAMESPACE"
}

# TODO: we should test that we cannot migrate and upgrade at the same time
#       (ie, from OSS v1 to AES v2)

exit 0
