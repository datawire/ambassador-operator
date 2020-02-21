#!/bin/bash

dummy_prov_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$dummy_prov_dir" ] || {
	echo "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}

# shellcheck source=../common.sh
source "$dummy_prov_dir/../../common.sh"

#########################################################################################

case $1 in
create)
	[ -n "$KUBECONFIG" ] || [ -n "$DEV_KUBECONFIG" ] || abort "the dummy cluster provider needs a KUBECONFIG/DEV_KUBECONFIG"
	[ -n "$DEV_REGISTRY" ] || abort "the dummy cluster provider needs a DEV_REGISTRY"
	;;

#
# get the environment vars
#
get-env)
	if [ -n "$KUBECONFIG" ]; then
		echo "DEV_KUBECONFIG=$KUBECONFIG"
		echo "KUBECONFIG=$KUBECONFIG"
	elif [ -n "$DEV_KUBECONFIG" ]; then
		echo "DEV_KUBECONFIG=$DEV_KUBECONFIG"
		echo "KUBECONFIG=$DEV_KUBECONFIG"
	fi

	if [ -n "$DEV_REGISTRY" ]; then
		echo "DEV_REGISTRY=$DEV_REGISTRY"
	fi
	;;

#
# return True if the cluster exists
#
exists)
	/bin/true
	;;

*)
	info "'$1' ignored for $CLUSTER_PROVIDER"
	;;

esac
