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

AMB_INSTALLATION_DUP_NAME=${AMB_INSTALLATION_NAME}-duplicate

# installs a second `AmbassadorInstallation`
apply_amb_install_duplicate() {
	cat <<EOF | kubectl apply $@ -f -
apiVersion: getambassador.io/v2
kind: AmbassadorInstallation
metadata:
  name: ${AMB_INSTALLATION_DUP_NAME}
spec:
  version: "*"
  logLevel: info
EOF
}

########################################################################################################################

pushd "$TOP_DIR" >/dev/null || exit 1

info "Installing the Operator..."
oper_install "yaml" "$TEST_NAMESPACE" || failed "could not deploy operator"
oper_wait_install -n "$TEST_NAMESPACE" || failed "the Ambassador operator is not alive"

info "Checking we can install Ambassador..."
amb_inst_apply_version "$AMB_VERSION" -n "$TEST_NAMESPACE" || failed "could not instruct the operator to install $AMB_VERSION"
sleep 1
info "Waiting for the Operator to install Ambassador"
if ! wait_amb_addr -n "$TEST_NAMESPACE"; then
	warn "Ambassador not installed. Dumping Operator's logs:"
	oper_logs_dump -n "$TEST_NAMESPACE"
	failed "could not get an Ambassador IP"
fi
passed "... good! Ambassador has been installed by the Operator!"

info "Applying another AmbassadorInstallation (should be detected as duplicate)"
apply_amb_install_duplicate -n "$TEST_NAMESPACE"
sleep 2
describe_dump_cmd="kubectl describe -n $TEST_NAMESPACE ambassadorinstallations ${AMB_INSTALLATION_DUP_NAME}"
wait_until "$describe_dump_cmd | grep -q DuplicateError" || {
	warn "Duplicate not detected:"
	eval "$describe_dump_cmd"
	warn "Dumping Operator's logs:"
	oper_logs_dump -n "$TEST_NAMESPACE"
	failed "${AMB_INSTALLATION_DUP_NAME} was not detected as a duplicate"
}
passed "... ${AMB_INSTALLATION_DUP_NAME} detected as a duplicate."

info "List of AmbassadorInstallations:"
kubectl get -n "$TEST_NAMESPACE" ambassadorinstallations

[ -n "$VERBOSE" ] && {
	info "Describe: Ambassador Operator deployment:" && oper_describe -n "$TEST_NAMESPACE"
	info "Describe: Ambassador deployment:" && amb_describe -n "$TEST_NAMESPACE"
}

info "Checking the version of Ambassador that has been deployed is $AMB_VERSION..."
if ! amb_check_image_tag "$AMB_VERSION" -n "$TEST_NAMESPACE"; then
	warn "wrong version installed. Dumping operator's logs:"
	oper_logs_dump -n "$TEST_NAMESPACE"
	failed "wrong version installed"
fi

amb_inst_check_success -n "$TEST_NAMESPACE" || {
	warn "Success not found in AmbassadorInstallation:"
	amb_inst_describe -n "$TEST_NAMESPACE"
	failed "Success not found in AmbassadorInstallation description"
}

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
