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
IMAGE_TAG_FIRST="1.5.5"
IMAGE_TAG_SECOND="1.6.0"

# released images that will be used for tests
CUSTOM_IMAGE_FIRST="${OFFICIAL_REGISTRY}/aes:${IMAGE_TAG_FIRST}"
CUSTOM_IMAGE_SECOND="${OFFICIAL_REGISTRY}/aes:${IMAGE_TAG_SECOND}"

########################################################################################################################

[ -z "$DEV_REGISTRY" ] && abort "no DEV_REGISTRY defined"
[ -z "$KUBECONFIG" ] && abort "no KUBECONFIG defined"

########################################################################################################################

info "Installing the Operator..."
oper_install "yaml" "$TEST_NAMESPACE" || failed "could not deploy operator"
oper_wait_install -n "$TEST_NAMESPACE" || failed "the Ambassador operator is not alive"

info "Installing Ambassador..."

info "Creating AmbassadorInstallation with baseImage=${CUSTOM_IMAGE_FIRST}..."
apply_amb_inst_image ${CUSTOM_IMAGE_FIRST} -n "$TEST_NAMESPACE"
info "AmbassadorInstallation created successfully..."

oper_wait_install_amb -n "$TEST_NAMESPACE" || abort "the Operator did not install Ambassador"

[ -n "$VERBOSE" ] && {
	info "Describe: Ambassador Operator deployment:" && oper_describe -n "$TEST_NAMESPACE"
	info "Describe: Ambassador deployment:" && amb_describe -n "$TEST_NAMESPACE"
}

info "Checking the version of Ambassador that has been deployed is $IMAGE_TAG_FIRST..."
if ! amb_check_image_tag "$IMAGE_TAG_FIRST" -n "$TEST_NAMESPACE"; then
	warn "Image not expected. Dumping Operator's logs:"
	oper_logs_dump -n "$TEST_NAMESPACE"
	failed "wrong version installed"
fi
passed "... good! Ambassador that has been deployed with $IMAGE_TAG_FIRST"

info "Upgrading Ambassador with baseImage=${CUSTOM_IMAGE_SECOND}..."
apply_amb_inst_image ${CUSTOM_IMAGE_SECOND} -n "$TEST_NAMESPACE"
if ! amb_wait_image_tag "$IMAGE_TAG_SECOND" -n "$TEST_NAMESPACE"; then
	oper_logs_dump -n "$TEST_NAMESPACE"
	failed "Upgrade to $IMAGE_TAG_SECOND failed"
fi

info "Checking the version of Ambassador that has been deployed is $IMAGE_TAG_SECOND..."
if ! amb_check_image_tag "$IMAGE_TAG_SECOND" -n "$TEST_NAMESPACE"; then
	warn "Image not expected:"
	oper_logs_dump -n "$TEST_NAMESPACE"
	failed "Upgrade to $IMAGE_TAG_SECOND failed"
fi
passed "... good! Ambassador's image has been changed to $IMAGE_TAG_SECOND"

amb_inst_check_success -n "$TEST_NAMESPACE" || {
	warn "Unexpected content in AmbassadorInstallation description:"
	amb_inst_describe -n "$TEST_NAMESPACE"
	failed "Success not found in AmbassadorInstallation description"
}

[ -n "$VERBOSE" ] && {
	info "Describe: AmbassadorInstallation:" && amb_inst_describe -n "$TEST_NAMESPACE"
	info "Logs: Ambassador operator" && oper_logs_dump -n "$TEST_NAMESPACE"
}

exit 0
