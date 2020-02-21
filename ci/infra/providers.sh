#!/bin/bash

providers_sh_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$providers_sh_dir" ] || {
	echo "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}
TOP_DIR=$(realpath $providers_sh_dir/../..)

script_name=$(basename ${0#-}) #- needed if sourced no path
this_script=$(basename ${BASH_SOURCE})

source "$TOP_DIR/ci/common.sh"

########################################################################################################################

# some tests directories
PROVIDERS_DIR="$providers_sh_dir/providers"

# use k3d as the default cluster provider
[ -n "$CLUSTER_PROVIDER" ] || export CLUSTER_PROVIDER="k3d"

########################################################################################################################

cluster_provider() {
	local exe_provider="$PROVIDERS_DIR/$CLUSTER_PROVIDER.sh"
	[ -x "$exe_provider" ] || abort "'$CLUSTER_PROVIDER' is not a valid cluster provider: no driver found at $exe_provider. Set the env var CLUSTER_PROVIDER to one of: $(ls_cluster_providers)."
	for action in $@; do
		info "(cluster provider: $CLUSTER_PROVIDER: $action)"
		"$exe_provider" "$action"
	done
}

ls_cluster_providers() {
	all_shs_in "$PROVIDERS_DIR/"
}

if [[ "${script_name}" == "${this_script}" ]]; then
	if [[ $# -gt 0 ]]; then
		case "$1" in
		ls)
			ls_cluster_providers
			;;

		*)
			cluster_provider "$1"
			;;
		esac
	fi
fi
