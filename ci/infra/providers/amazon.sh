#!/bin/bash

amazon_provider_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$amazon_provider_dir" ] || {
	echo "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}

# shellcheck source=../common.sh
source "$amazon_provider_dir/../../common.sh"

#########################################################################################

# the az executable
EXE_EKSCTL="$HOME/bin/eksctl"

EXE_EKSCTL_URL="https://github.com/weaveworks/eksctl/releases/download/latest_release/eksctl_$(uname -s)_amd64.tar.gz"

# the cluster name
EKS_CLUSTER="amb-oper-tests"

# number of nodes
EKS_CLUSTER_NUM_NODES=1

# the registry name
EKS_REGISTRY="amb-oper-reg"

# resource group
AZ_RES_GRP="amb-oper-tests"

# cluster location
AZ_LOC="eastus"

DEF_KUBECONFIG="$HOME/.kube/config"

#########################################################################################

mkdir -p "$HOME/.kube"

case $1 in
#
# setup and cleanup
#
setup)
	mkdir -p "$HOME/bin"
	export PATH=$HOME/bin:$PATH

	if ! command_exists "aws"; then
		info "Installing aws"
		pip install awscli --upgrade
	else
		info "aws seems to be installed"
	fi

	if ! command_exists $EXE_EKSCTL; then
		info "Installing $EXE_EKSCTL"
		curl --silent --location $EXE_EKSCTL_URL | tar xz -C /tmp
		mv /tmp/eksctl $EXE_EKSCTL
		chmod 755 $EXE_EKSCTL
	else
		info "$(basename $EXE_EKSCTL) seems to be installed"
	fi
	;;

cleanup)
	info "Cleaning up Amazon EKS..."
	;;

#
# create and destroy tyhe cluster
#
create)
	if [ -f "$(get_kubeconfig)" ]; then
		info "cluster has already been created: releasing"
		$0 delete
	fi

	[ -n "$AWS_ACCESS_KEY_ID" ] || abort "no AWS_ACCESS_KEY_ID defined"
	[ -n "$AWS_SECRET_ACCESS_KEY" ] || abort "no AWS_SECRET_ACCESS_KEY defined"

	info "Creating a Amazon EKS cluster in $AZ_RES_GRP..."
	$EXE_EKSCTL create cluster \
		--name "$EKS_CLUSTER" \
		--version 1.14 \
		--region us-west-2 \
		--nodegroup-name standard-workers \
		--node-type t3.medium \
		--nodes $EKS_CLUSTER_NUM_NODES \
		--ssh-access \
		--ssh-public-key my-public-key.pub \
		--managed ||
		abort "could not create cluster $EKS_CLUSTER"

	info "Getting credentials for cluster $EKS_CLUSTER..."
	mkdir -p "$(dirname $DEF_KUBECONFIG)"
	$EXE_EKSCTL utils write-kubeconfig \
		--cluster="$EKS_CLUSTER" \
		--kubeconfig="$DEF_KUBECONFIG" ||
		abort "could not create kubeconfig for $EKS_CLUSTER"

	info "Doing a quick sanity check on that cluster $EKS_CLUSTER..."
	kubectl -n default get service kubernetes ||
		abort "Amazon EKS was not able to create a valid kubernetes cluster"

	info "Amazon EKS cluster created"
	;;

delete)
	# TODO
	;;

#
# the registry
#
create-registry)
	info "Creating a Amazon EKS registry..."
	# TODO
	;;

delete-registry)
	# TODO
	;;

#
# return True if the cluster exists
#
exists)
	# TODO
	;;

#
# get the environment vars
#
get-env)
	echo "DEV_KUBECONFIG=$DEF_KUBECONFIG"
	echo "KUBECONFIG=$DEF_KUBECONFIG"

	# TODO
	echo "DEV_REGISTRY="
	;;

*)
	info "'$1' ignored for $CLUSTER_PROVIDER"
	;;

esac
