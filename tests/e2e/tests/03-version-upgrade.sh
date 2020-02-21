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
AMB_VERSION_FIRST="1.0.0"
AMB_VERSION_SECOND_EXP="1.*"

########################################################################################################################

[ -z "$DEV_REGISTRY" ] && abort "no DEV_REGISTRY defined"
[ -z "$KUBECONFIG" ] && abort "no KUBECONFIG defined"

########################################################################################################################

info "Installing the Operator..."
oper_install "yaml" "$TEST_NAMESPACE" || failed "could not deploy operator"
oper_wait_install -n "$TEST_NAMESPACE" || failed "the Ambassador operator is not alive"

info "Installing Ambassador with version=${AMB_VERSION_FIRST}..."
amb_inst_apply_version "$AMB_VERSION_FIRST" -n "$TEST_NAMESPACE" || failed "coud not instruct the operator to install ${AMB_VERSION_FIRST}"
passed "... instructed the operator to install ${AMB_VERSION_FIRST}"

info "Waiting for the Operator to install Ambassador"
if ! wait_amb_addr -n "$TEST_NAMESPACE"; then
	warn "Ambassador not installed. Dumping Operator's logs:"
	oper_logs_dump -n "$TEST_NAMESPACE"
	failed "could not get an Ambassador IP"
fi
passed "... good! Ambassador has been installed by the Operator!"

[ -n "$VERBOSE" ] && {
	info "Describe: Ambassador Operator deployment:" && oper_describe -n "$TEST_NAMESPACE"
	info "Describe: Ambassador deployment:" && amb_describe -n "$TEST_NAMESPACE"
}

info "Checking the version of Ambassador that has been deployed is $AMB_VERSION_FIRST..."
if ! amb_check_image_tag "$AMB_VERSION_FIRST" -n "$TEST_NAMESPACE"; then
	oper_logs_dump -n "$TEST_NAMESPACE"
	failed "wrong version installed"
fi
passed "... good! The version is $AMB_VERSION_FIRST"

info "Upgrading Ambassador to version $AMB_VERSION_SECOND_EXP..."
amb_inst_apply_version "$AMB_VERSION_SECOND_EXP" -n "$TEST_NAMESPACE" || failed "could not instruct the operator to install $AMB_VERSION_SECOND_EXP"
passed "... instructed the operator to install $AMB_VERSION_SECOND_EXP."

info "Waiting until the version of Ambassador that has been deployed is greater than ${AMB_VERSION_FIRST}..."
if ! amb_wait_image_tag_gt "$AMB_VERSION_FIRST" -n "$TEST_NAMESPACE"; then
	oper_logs_dump -n "$TEST_NAMESPACE"
	failed "Upgrade to $AMB_VERSION_SECOND_EXP failed"
fi
passed "... good! The version has been bumped to $(amb_get_image_tag -n $TEST_NAMESPACE) with $AMB_VERSION_SECOND_EXP"

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
