#!/bin/bash

kubernaut_prov_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$kubernaut_prov_dir" ] || {
	echo "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}

# shellcheck source=../common.sh
source "$kubernaut_prov_dir/../../common.sh"

#########################################################################################

CLAIM_NAME="operator-tests-${USER}-$(uuidgen)"
CLAIM_FILENAME="$HOME/.kube/kubernaut-claim.txt"

KUBERNAUT_CONF="$TOP_DIR/.circleci/kconf.b64"

# the registry used when using kubernaut
KUBERNAUT_REGISTRY_HOSTNAME="quay.io"
KUBERNAUT_REGISTRY="$KUBERNAUT_REGISTRY_HOSTNAME/datawire-dev"

#########################################################################################

mkdir -p "$HOME/.kube"

get_kubeconfig() {
	mkdir -p "$HOME/.kube"
	local kc="$HOME/.kube/$(cat $CLAIM_FILENAME 2>/dev/null).yaml"
	[ -f "$kc" ] && echo "$kc"
}

case $1 in
#
# setup and cleanup
#
setup)
	mkdir -p "$HOME/bin"
	export PATH=$HOME/bin:$PATH

	if ! command_exists $EXE_KUBERNAUT; then
		info "Installing kubernaut"
		download_exe "$EXE_KUBERNAUT" "$EXE_KUBERNAUT_URL"
	else
		info "kubernaut seems to be installed"
	fi

	if [ -f "$KUBERNAUT_CONF" ]; then
		info "Creating kubernaut config..."
		base64 -d <"$KUBERNAUT_CONF" | (
			cd ~
			tar xzf -
		)
		echo "$CLAIM_NAME" >"$CLAIM_FILENAME"
	else
		warn "no kubernaut configuration found at $KUBERNAUT_CONF"
	fi
	;;

cleanup)
	info "Cleaning up kubernaut..."
	rm -rf ~/.kubernaut
	;;

#
# create and destroy tyhe cluster
#
create)
	if [ -f "$(get_kubeconfig)" ]; then
		info "cluster has already been created: releasing"
		$0 delete
	fi

	info "Creating a kubernaut cluster for $CLAIM_NAME..."
	kubernaut claims create --name "$CLAIM_NAME" --cluster-group main || abort "could not claim $CLAIM_NAME"

	info "Saving claim name in $CLAIM_FILENAME"
	echo "$CLAIM_NAME" >$CLAIM_FILENAME

	info "Doing a quick sanity check on that cluster..."
	kubectl --kubeconfig "$(get_kubeconfig)" -n default get service kubernetes ||
		abort "kubernaut was not able to create a valid kubernetes cluster"

	info "kubernaut cluster created"
	;;

delete)
	if [ -f "$CLAIM_FILENAME" ]; then
		info "Releasing kubernaut claim..."
		kubernaut claims delete "$(cat $CLAIM_FILENAME)"

		rm -f "$(get_kubeconfig)"
		rm -f "$CLAIM_FILENAME"
	fi
	;;

#
# the registry
#
create-registry)
	if [ -n "$DOCKER_USER" ] && [ -n "$DOCKER_PASSWORD" ]; then
		docker login -u="$DOCKER_USER" -p="$DOCKER_PASSWORD" $KUBERNAUT_REGISTRY_HOSTNAME
	else
		warn "no DOCKER_USER/DOCKER_PASSWORD provided for logging in $KUBERNAUT_REGISTRY_HOSTNAME"
	fi
	;;

delete-registry) ;;

#
# return True if the cluster exists
#
exists)
	test -f "$(get_kubeconfig)"
	;;

#
# get the environment vars
#
get-env)
	kc="$(get_kubeconfig)"
	if [ -n "$kc" ]; then
		echo "DEV_KUBECONFIG=$kc"
		echo "KUBECONFIG=$kc"
	fi

	echo "DEV_REGISTRY=$KUBERNAUT_REGISTRY"
	;;

*)
	info "'$1' ignored for $CLUSTER_PROVIDER"
	;;

esac
