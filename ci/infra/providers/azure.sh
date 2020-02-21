#!/bin/bash

# Input env vars:
#
# - AZ_AUTH (optional)
# - AZ_AUTH_FILE (optional)
# - AZ_USERNAME (optional)
# - AZ_TENANT (optional)
# - AZ_PASSWORD (optional)
#
# see https://github.com/datawire/ambassador-operator/blob/master/ci/infra/CREDENTIALS.md#Azure
#

azure_prov_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$azure_prov_dir" ] || {
	echo "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}

# shellcheck source=../common.sh
source "$azure_prov_dir/../../common.sh"

user=$(whoami)
num="${TRAVIS_BUILD_ID:-0}"

#########################################################################################

# the az executable
EXE_AZ="az"

# the cluster name
AZ_CLUSTER="${CLUSTER_NAME:-amb-oper-tests-$user-$num}"

# number of nodes
AZ_CLUSTER_NUM_NODES="${CLUSTER_SIZE:-1}"

# the node size (see https://docs.microsoft.com/en-us/azure/cloud-services/cloud-services-sizes-specs)
AZ_CLUSTER_NODE_SIZE="${CLUSTER_MACHINE:-Standard_D2s_v3}"

# the registry name (must conform to the following pattern: '^[a-zA-Z0-9]*$')
AZ_REGISTRY="AmbassadorOperatorTests${num}"

# resource group
AZ_RES_GRP="$AZ_CLUSTER"

# set to non-empty for managin the reosurce group
MANAGE_RES_GRP=1

# cluster location
AZ_LOC="${CLUSTER_REGION:-eastus}"

# the file for auth
AZ_AUTH_FILE="${AZ_AUTH_FILE:-/tmp/az-auth.json}"

#########################################################################################

# args for "az aks create"
AZ_CREATE_ARGS="--network-plugin=azure --network-policy=azure"

# args for "az aks delete"
AZ_DELETE_ARGS="--yes"

#########################################################################################

export PATH=$PATH:${AZ_INSTALL_DIR}/bin

az_check_registry() {
	$EXE_AZ acr show -n "$AZ_REGISTRY" >/dev/null 2>&1
}

az_get_logged_in_user() {
	$EXE_AZ account show | jq ".user.name" | tr -d "\"" 2>/dev/null
}

# get a cluster-specific kubeconfig
az_get_kubeconfig() {
	local kc_d="$(dirname $DEF_KUBECONFIG)"
	echo "$kc_d/azure-${AZ_CLUSTER}.yaml"
}

# wait for the registry to be ready
az_wait_registry() {
	info "Waiting for the registry $AZ_REGISTRY to be ready (max $DEF_WAIT_TIMEOUT seconds)"
	local start_time=$(timestamp)
	until timeout_from $start_time || az_check_registry; do
		info "... still waiting for registry"
		sleep 1
	done
	! timeout_from $start_time
}

az_get_registry_hostname() {
	$EXE_AZ acr show --name "$AZ_REGISTRY" | jq ".loginServer" | tr -d "\""
}

# get a valid JSON authentication file
az_get_auth_file() {
	[ -n "$AZ_AUTH_FILE" ] || [ -n "$AZ_AUTH" ] || abort "no AZ_AUTH/AZ_AUTH_FILE provided"

	if [ ! -f "$AZ_AUTH_FILE" ] && [ -n "$AZ_AUTH" ]; then
		info "(using authentication credentials from the AZ_AUTH env var to '$AZ_AUTH_FILE')"
		rm -f "$AZ_AUTH_FILE"
		echo "$AZ_AUTH" | base64 -d >"$AZ_AUTH_FILE"
	fi
	if [ -f "$AZ_AUTH_FILE" ]; then
		info "(using credentials from '$AZ_AUTH_FILE')"
	else
		abort "failed to create authentication file '$AZ_AUTH_FILE'"
	fi
}

# get the email in a JSON authentication file
az_attr_in_auth_file() {
	az_get_auth_file && cat "$AZ_AUTH_FILE" | jq ".$1" | tr -d "\"" | grep -v "null"
}

az_username_in_auth_file() { az_attr_in_auth_file "appId"; }
az_tenant_in_auth_file() { az_attr_in_auth_file "tenant"; }
az_password_in_auth_file() { az_attr_in_auth_file "password"; }

az_username() {
	if [ -z "$AZ_USERNAME" ]; then
		az_username_in_auth_file
	else
		echo "$AZ_USERNAME"
	fi
}

az_tenant() {
	if [ -z "$AZ_TENANT" ]; then
		az_tenant_in_auth_file
	else
		echo "$AZ_TENANT"
	fi
}

az_password() {
	if [ -z "$AZ_PASSWORD" ]; then
		az_password_in_auth_file
	else
		echo "$AZ_PASSWORD"
	fi
}

# returns True if the cluster can be described
az_exists_cluster() {
	$EXE_AZ aks show --name "$AZ_CLUSTER" --resource-group "$AZ_RES_GRP" >/dev/null 2>&1
}

# returns True if the registry exists
az_registry_exists() {
	$EXE_AZ acr show --resource-group "$AZ_RES_GRP" --name "$AZ_REGISTRY" --yes >/dev/null 2>&1
}

# login into Azure (checking we are not already logged in)
az_login() {
	local username="$(az_username)"
	local password="$(az_password)"
	local tenant="$(az_tenant)"

	[ -n "$username" ] || abort "could not obtain the Azure username from AZ_USERNAME or AZ_AUTH/AZ_AUTH_FILE"
	[ -n "$password" ] || abort "could not obtain the Azure password from AZ_PASSWORD or AZ_AUTH/AZ_AUTH_FILE"
	[ -n "$tenant" ] || abort "could not obtain the Azure tenant from AZ_TENANT or AZ_AUTH/AZ_AUTH_FILE"

	current_user=$(az_get_logged_in_user)
	if [ "$username" != "$current_user" ]; then
		info "Loging in as $username (tenant: $tenant) (current: $current_user)"
		$EXE_AZ login --service-principal \
			--username "$username" --password "$password" --tenant "$tenant" ||
			abort "could not authenticate"
		passed "... authenticated as $username"
	else
		info "Already logged in as $username (tenant: $tenant)"
	fi
}

# logout from Azure
az_logout() {
	info "Logging out"
	$EXE_AZ logout || warn "failed to logout"
}

#########################################################################################

mkdir -p "$HOME/.kube"

case $1 in
#
# setup and cleanup
#
setup)
	mkdir -p "$HOME/bin"
	export PATH=$HOME/bin:$PATH

	info "Installing dependencies..."
	sudo apt-get update
	sudo apt-get install python-dev ca-certificates curl apt-transport-https lsb-release gnupg

	info "Installing public key..."
	curl -sL https://packages.microsoft.com/keys/microsoft.asc |
		gpg --dearmor |
		sudo tee /etc/apt/trusted.gpg.d/microsoft.asc.gpg >/dev/null

	info "Adding Azure packages repo..."
	az_repo=$(lsb_release -cs)
	echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $az_repo main" |
		sudo tee /etc/apt/sources.list.d/azure-cli.list

	info "Installing the azure-cli..."
	sudo apt-get update
	sudo apt-get install azure-cli
	command_exists $EXE_AZ || abort "$EXE_AZ has not been properly installed."
	passed "... azure client installed"

	info "Installing aks-preview..."
	$EXE_AZ extension add --name aks-preview || abort "aks-preview has not been properly installed."
	passed "... aks-preview installed"
	;;

cleanup)
	info "Removing a azure cluster $AZ_CLUSTER (in $AZ_RES_GRP) (asynchronously)..."
	$EXE_AZ aks delete --no-wait --resource-group "$AZ_RES_GRP" --name "$AZ_CLUSTER" $AZ_DELETE_ARGS ||
		warn "could not delete cluster $AZ_CLUSTER"
	passed "... Cluster $AZ_CLUSTER deleted."

	if [ -n "$MANAGE_RES_GRP" ]; then
		info "Releasing azure resources group $AZ_RES_GRP..."
		$EXE_AZ group delete --yes --name "$AZ_RES_GRP" --yes --no-wait ||
			abort "could not delete group $AZ_RES_GRP"
		passed "... Group $AZ_RES_GRP deleted."

		info "Releasing azure nodes resources group nodes-$AZ_RES_GRP..."
		$EXE_AZ group delete --yes --name "nodes-$AZ_RES_GRP" --yes --no-wait ||
			abort "could not delete group nodes-$AZ_RES_GRP"
		passed "... Group $AZ_RES_GRP deleted."
	fi

	info "Loging out"
	az_logout || warn "could not logout... ignored."
	passed
	;;

#
# create and destroy tyhe cluster
#
create)
	az_login || abort "login failed: cluster creation aborted"

	info "Checking if cluster $AZ_CLUSTER already exists..."
	if az_exists_cluster; then
		if [ -n "$CLUSTER_REUSE" ]; then
			info "$AZ_CLUSTER already exists: CLUSTER_REUSE=true: exitting"
			exit 0
		else
			info "$AZ_CLUSTER already ewxists: deleting (synchronously)"
			$EXE_AZ aks delete --resource-group "$AZ_RES_GRP" --name "$AZ_CLUSTER" $AZ_DELETE_ARGS ||
				abort "could not delete cluster $AZ_CLUSTER"
			passed "... Cluster $AZ_CLUSTER deleted."
		fi
	else
		info "$AZ_CLUSTER does not seem to exist: will create now."
	fi

	# check that the location is valid
	if [ -n "$AZ_LOC" ]; then
		info "Checking $AZ_LOC exists"
		$EXE_AZ account list-locations --query "[].name" | grep -q "$AZ_LOC" || {
			info "$AZ_LOC does not exist. List of locations available:"
			$EXE_AZ account list-locations --query "[].name"
			abort "$AZ_LOC does not exist"
		}
		passed "... $AZ_LOC is ok"
	fi

	# check that the VM size is available in that location
	if [ -n "$AZ_CLUSTER_NODE_SIZE" ]; then
		info "Checking $AZ_CLUSTER_NODE_SIZE exists in $AZ_LOC"
		$EXE_AZ vm list-sizes -l "$AZ_LOC" --query "[].name" | grep -q "$AZ_CLUSTER_NODE_SIZE" || {
			info "$AZ_CLUSTER_NODE_SIZE does not exist in $AZ_LOC. List of VM sizes available in $AZ_LOC:"
			$EXE_AZ vm list-sizes -l "$AZ_LOC" --query "[].name"
			abort "$AZ_CLUSTER_NODE_SIZE does not exist in $AZ_LOC"
		}
		passed "... $AZ_CLUSTER_NODE_SIZE is ok in $AZ_LOC"
	fi

	if [ -n "$MANAGE_RES_GRP" ]; then
		info "Creating a azure resource group $AZ_RES_GRP in $AZ_LOC..."
		$EXE_AZ group create --name "$AZ_RES_GRP" --location "$AZ_LOC" ||
			abort "could not create resource group $AZ_RES_GRP"
		info "Group $AZ_RES_GRP created."
	else
		info "Resource group not managed."
	fi

	username="$(az_username)"
	password="$(az_password)"
	info "Creating a azure cluster $AZ_CLUSTER (in $AZ_RES_GRP)..."
	$EXE_AZ aks create \
		--resource-group "$AZ_RES_GRP" \
		--node-resource-group "nodes-$AZ_RES_GRP" \
		--name "$AZ_CLUSTER" \
		--service-principal "$username" \
		--client-secret "$password" \
		--node-count $AZ_CLUSTER_NUM_NODES \
		--node-vm-size "$AZ_CLUSTER_NODE_SIZE" \
		--enable-addons monitoring \
		--generate-ssh-keys \
		$AZ_CREATE_ARGS || {
		info "could not create cluster $AZ_CLUSTER: destroying resources already created..."
		$0 delete
		abort "could not create cluster $AZ_CLUSTER"
	}
	passed "... Cluster $AZ_CLUSTER created."

	if ! command_exists kubectl; then
		info "Connecting to cluster $AZ_CLUSTER..."
		$EXE_AZ aks install-cli || abort "could not install tools for cluster $AZ_CLUSTER"
		passed "... Cli tools installed."
	fi

	kc="$(az_get_kubeconfig)"
	mkdir -p "$kc"

	info "Getting credentials (kubeconfig) for cluster $AZ_CLUSTER..."
	rm -rf "$kc"
	$EXE_AZ aks get-credentials --resource-group "$AZ_RES_GRP" \
		--name "$AZ_CLUSTER" --overwrite-existing --file "$kc" ||
		abort "could not create cluster $AZ_CLUSTER"
	[ -f "$kc" ] || abort "no kubeconfig generated in $kc"
	passed "... kubeconfig saved as $kc."

	info "Nodes in the cluster:"
	$EXE_AZ vmss list --resource-group "$AZ_RES_GRP" --query '[0].name' -o tsv || /bin/true

	info "Doing a quick sanity check on $AZ_CLUSTER (with $kc)"
	kubectl --kubeconfig="$kc" -n default get service kubernetes ||
		abort "azure was not able to create a valid kubernetes cluster"
	passed "... Azure cluster $AZ_CLUSTER created successfully (in $AZ_RES_GRP)."
	;;

delete)
	if [ -n "$CLUSTER_REUSE" ]; then
		info "cluster will not be deleted: CLUSTER_REUSE=true: exitting"
		exit 0
	fi

	az_login || abort "cluster deletion aborted"
	if az_exists_cluster; then
		info "Removing a azure cluster $AZ_CLUSTER (in $AZ_RES_GRP) (asynchronously)..."
		$EXE_AZ aks delete --no-wait --resource-group "$AZ_RES_GRP" --name "$AZ_CLUSTER" $AZ_DELETE_ARGS ||
			abort "could not delete cluster $AZ_CLUSTER"
		passed "... Cluster $AZ_CLUSTER deleted."

		if [ -n "$MANAGE_RES_GRP" ]; then
			info "Releasing azure resources group $AZ_RES_GRP..."
			$EXE_AZ group delete --yes --name "$AZ_RES_GRP" --yes --no-wait ||
				abort "could not delete group $AZ_RES_GRP"
			passed "... Group $AZ_RES_GRP deleted."

			info "Releasing azure nodes resources group nodes-$AZ_RES_GRP..."
			$EXE_AZ group delete --yes --name "nodes-$AZ_RES_GRP" --yes --no-wait ||
				abort "could not delete group nodes-$AZ_RES_GRP"
			passed "... Group $AZ_RES_GRP deleted."
		fi
	fi

	kc="$(az_get_kubeconfig)"
	if [ -f $kc ]; then
		info "Removing kubeconfig file"
		rm -f "$kc"
		passed "... $kc removed."
	fi
	;;

#
# the registry
#
create-registry)
	az_login || abort "registry creation aborted"

	info "Creating a azure registry $AZ_REGISTRY (in $AZ_RES_GRP)..."
	$EXE_AZ acr create --resource-group "$AZ_RES_GRP" --name "$AZ_REGISTRY" --sku Basic ||
		abort "could not create a registry"
	passed "... Registry $AZ_REGISTRY created."

	az_wait_registry ||
		warn "registry $AZ_REGISTRY does not seem to be alive: trying to login anyway..."

	info "Logging into the registry $AZ_REGISTRY..."
	$EXE_AZ acr login --name "$AZ_REGISTRY" || warn "not sure if login into the registry has been ok"
	;;

delete-registry)
	info "Deleting a azure registry $AZ_REGISTRY (in $AZ_RES_GRP)..."
	az_login || abort "registry deletion aborted"
	az_registry_exists &&
		$EXE_AZ acr delete --resource-group "$AZ_RES_GRP" --name "$AZ_REGISTRY" --yes
	passed "... Registry $AZ_REGISTRY deleted."
	;;

#
# return True if the cluster exists
#
exists)
	az_login && az_exists_cluster
	;;

#
# get the environment vars
#
get-env)
	kc="$(az_get_kubeconfig)"
	registry=$(az_get_registry_hostname)

	echo "DEV_KUBECONFIG=$kc"
	echo "KUBECONFIG=$kc"
	echo "DEV_REGISTRY=$registry"

	echo "CLUSTER_NAME=$AZ_CLUSTER"
	echo "CLUSTER_SIZE=$AZ_CLUSTER_NUM_NODES"
	echo "CLUSTER_MACHINE=$AZ_CLUSTER_NODE_SIZE"
	echo "CLUSTER_REGION=$AZ_LOC"

	# azure-specific variables
	echo "AZ_CLUSTER=$AZ_CLUSTER"
	echo "AZ_CLUSTER_NUM_NODES=$AZ_CLUSTER_NUM_NODES"
	echo "AZ_CLUSTER_NODE_SIZE=$AZ_CLUSTER_NODE_SIZE"
	echo "AZ_REGISTRY=$AZ_REGISTRY"
	echo "AZ_RES_GRP=$AZ_RES_GRP"
	echo "MANAGE_RES_GRP=$MANAGE_RES_GRP"
	echo "AZ_LOC=$AZ_LOC"
	;;

*)
	[ -n "$1" ] || abort "no argument provided"
	info "'$1' ignored for $CLUSTER_PROVIDER"
	;;

esac
