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
AMB_VERSION="1.0.0"

########################################################################################################################

[ -z "$DEV_REGISTRY" ] && abort "no DEV_REGISTRY defined"
[ -z "$KUBECONFIG" ] && abort "no KUBECONFIG defined"

########################################################################################################################

pushd "$TOP_DIR" >/dev/null || exit 1

info "Installing operator with Helm..."
oper_install "helm" "$TEST_NAMESPACE" || failed "could not deploy operator"
oper_wait_install -n "$TEST_NAMESPACE" || failed "the Ambassador operator is not alive"

info "Checking we can install Ambassador..."
amb_inst_apply_version "$AMB_VERSION" -n "$TEST_NAMESPACE" || failed "could not instruct the operator to install $AMB_VERSION"

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

info "Checking the version of Ambassador that has been deployed is $AMB_VERSION..."
if ! amb_check_image_tag "$AMB_VERSION" -n "$TEST_NAMESPACE"; then
	oper_logs_dump -n "$TEST_NAMESPACE"
	failed "wrong version installed"
fi

amb_inst_check_success -n "$TEST_NAMESPACE" || failed "Success not found in AmbassadorInstallation description"

[ -n "$VERBOSE" ] && {
	info "Describe: AmbassadorInstallation:" && amb_inst_describe -n "$TEST_NAMESPACE"
	info "Logs: Ambassador operator" && oper_logs_dump -n "$TEST_NAMESPACE"
}

info "Checking we can remove Ambassador when the AmbassadorInstallation is deleted"
amb_inst_delete -n "$TEST_NAMESPACE" || failed "could not remove AmbassadorInstallation"

sleep 5

info "Waiting for the Operator to remove Ambassador"
wait_not_amb_addr -n "$TEST_NAMESPACE" || {
	warn "Ambassador not uninstalled. Dumping Operator's logs:"
	oper_logs_dump -n "$TEST_NAMESPACE"
	failed "Ambassador was sill returning an IP after uninstallationh"
}
passed "... good! Ambassador seems to be uninstalled after removing the AmbassadorInstallation."

[ -n "$VERBOSE" ] && info "Logs: Ambassador operator (after removing the AmbassadorInstallation)" && oper_logs_dump -n "$TEST_NAMESPACE"

amb_inst_check_uninstalled -n "$TEST_NAMESPACE" || {
	warn "Logs: Ambassador operator (after removing the AmbassadorInstallation)"
	oper_logs_dump -n "$TEST_NAMESPACE"
	failed "no 'Uninstalled release' line found in the Operator logs"
}
passed "... good! we have found the uninstallation message in the logs"

sleep 5

oper_uninstall "$TEST_NAMESPACE" || failed "could not uninstall the Ambassador operator in namespace '$TEST_NAMESPACE'"

popd >/dev/null || exit 1
exit 0
