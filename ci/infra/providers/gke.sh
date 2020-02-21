#!/bin/bash

# Input env vars:
#
# - GKE_AUTH  (optional)
# - GKE_AUTH_FILE (optional)
#
# see https://github.com/datawire/ambassador-operator/blob/master/ci/infra/CREDENTIALS.md#GKE
#

gke_provider_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$gke_provider_dir" ] || {
	echo "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}

# shellcheck source=../common.sh
source "$gke_provider_dir/../../common.sh"

user=$(whoami)
num="${TRAVIS_BUILD_ID:-0}"

#########################################################################################

# installation directory
# NOTE: the last part must be "google-cloud-sdk"... you better do not change this
GKE_INSTALL_DIR=${GKE_INSTALL_DIR:-$HOME/google-cloud-sdk}

# the az executable
EXE_GCLOUD="$GKE_INSTALL_DIR/bin/gcloud"

# the cluster name
GKE_CLUSTER="${CLUSTER_NAME:-amb-oper-tests-$user-$num}"

# number of nodes
GKE_CLUSTER_NUM_NODES="${CLUSTER_SIZE:-1}"

# machine type
GKE_CLUSTER_MACHINE_TYPE="${CLUSTER_MACHINE:n2-standard-2}"

# cluster region (https://cloud.google.com/compute/docs/regions-zones?hl=en#available)
GKE_LOC_REGION="${CLUSTER_REGION:-us-east1-b}"

# the file for auth
GKE_AUTH_FILE="${GKE_AUTH_FILE:-/tmp/gke-auth.json}"

#########################################################################################

GKE_KUBECONFIG=$HOME/.kube/config

# extra components to install
GKE_EXTRA_COMPONENTS=""

GKE_REGISTRY_HOST="gcr.io"

#########################################################################################

mkdir -p "$(dirname $GKE_KUBECONFIG)"
export PATH=$PATH:${GKE_INSTALL_DIR}/bin

# get the email in a JSON authentication file
gke_attr_in_auth_file() {
	local file="$1"
	local attr="$2"
	cat "$file" | jq ".$attr" | tr -d "\""
}

gke_email_in_auth_file() { gke_attr_in_auth_file "$1" "client_email"; }
gke_project_in_auth_file() { gke_attr_in_auth_file "$1" "project_id"; }

# returns True if the cluster can be described
gke_exists_cluster() {
	$EXE_GCLOUD container clusters describe --region "$GKE_LOC_REGION" "$GKE_CLUSTER" >/dev/null 2>&1
}

# get a valid JSON authentication file
gke_get_auth_file() {
	[ -n "$GKE_AUTH" ] || [ -f "$GKE_AUTH_FILE" ] || abort "no GKE_AUTH var provided"

	if [ ! -f "$GKE_AUTH_FILE" ]; then
		info "Getting the authentication credentials from the GKE_AUTH env var to $GKE_AUTH_FILE"
		rm -f "$GKE_AUTH_FILE"
		echo "$GKE_AUTH" | base64 -d >"$GKE_AUTH_FILE"
	fi
	[ -f "$GKE_AUTH_FILE" ] || abort "$GKE_AUTH_FILE not created successfully"
}

# return True if there is an active account (corresponding to the current auth file)
gke_active_account() {
	gke_get_auth_file || return 1
	local email=$(gke_email_in_auth_file "$GKE_AUTH_FILE")
	info "(checking if $email is the active account)"
	$EXE_GCLOUD auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q "$email"
}

# retrurn True if the <machine> type is available in the <region>
gke_exists_machine_in_region() {
	local machine="$1"
	local region="$2"
	gcloud compute machine-types list --filter="zone: $region" --format=value"(NAME)" | grep -q "$machine"
}

gke_docker_registry() {
	local project=$($EXE_GCLOUD config get-value project)
	[ -n "$project" ] || abort "no project obtained (probably no auth set yet)"
	echo "$GKE_REGISTRY_HOST/$project"
}

gke_login() {
	gke_get_auth_file || return 1

	info "Authenticating from $GKE_AUTH_FILE"
	local email=$(gke_email_in_auth_file "$GKE_AUTH_FILE")
	info "... using email=$email"
	$EXE_GCLOUD auth activate-service-account "$email" --key-file="$GKE_AUTH_FILE" || abort "could not authenticate"
	passed "... authenticated as $email"

	info "Configuring the Docker registry"
	$EXE_GCLOUD auth print-access-token |
		docker login -u oauth2accesstoken --password-stdin "https://${GKE_REGISTRY_HOST}" ||
		abort "could not authenticate for Docker on ${GKE_REGISTRY_HOST}"
	passed "... Docker registry configured for ${GKE_REGISTRY_HOST}"

	info "Setting compute region: $GKE_LOC_REGION"
	$EXE_GCLOUD config set compute/region "$GKE_LOC_REGION" || abort "could not set region $GKE_LOC_REGION"
	passed "... region set"

	project=$(gke_project_in_auth_file "$GKE_AUTH_FILE")
	info "Setting project: $project"
	$EXE_GCLOUD config set core/project "$project"
	passed "... project set"

	info "Getting some info from GKE:"
	$EXE_GCLOUD info || abort "could not get info"

	info "Selecting $email as active account"
	$EXE_GCLOUD config set account "$email"
	passed "... $email selected"
}

gke_logout() {
	gke_get_auth_file || /bin/true
	local email=$(gke_email_in_auth_file "$GKE_AUTH_FILE")

	info "Revoking auth for $email"
	if [ -n "$email" ]; then
		$EXE_GCLOUD auth revoke "$email" || warn "failed to revoke auth for $email"
	else
		warn "no login to revoke"
	fi
}

#########################################################################################

case $1 in
#
# setup and cleanup
#
setup)
	mkdir -p "$HOME/bin"
	export PATH=$HOME/bin:$PATH

	if [ -x "$EXE_GCLOUD" ]; then
		info "Google Cloud SDK seems to be installed at $GKE_INSTALL_DIR"
	else
		info "Installing Google Cloud SDK"
		curl https://sdk.cloud.google.com >/tmp/install.sh &&
			bash /tmp/install.sh --disable-prompts --install-dir="$(dirname $GKE_INSTALL_DIR)" >/dev/null

		[ $? -eq 0 ] || abort "gcloud copuld not be installed"
		[ -x "$EXE_GCLOUD" ] || abort "gcloud not available at $EXE_GCLOUD after installation"
	fi

	if [ -n "$GKE_EXTRA_COMPONENTS" ]; then
		info "Installing extra components:"
		for comp in $GKE_EXTRA_COMPONENTS; do
			$EXE_GCLOUD components install --quiet $comp || abort "could not install $comp"
		done
		info "done"
	fi
	;;

cleanup)
	info "Cleaning up GKE..."

	gke_active_account || gke_login

	info "Deleting cluster $GKE_CLUSTER"
	$EXE_GCLOUD container clusters delete --quiet --async --region "$GKE_LOC_REGION" "$GKE_CLUSTER" || /bin/true

	gke_logout || warn "could not logout"

	rm -rf $HOME/.config/gcloud
	;;

#
# create and destroy tyhe cluster
#
create)
	gke_active_account || gke_login

	if gke_exists_cluster; then
		if [ -n "$CLUSTER_REUSE" ]; then
			info "cluster already exists: CLUSTER_REUSE=true: exitting"
			exit 0
		else
			info "cluster has already been created: releasing"
			$0 delete
		fi
	fi

	info "Creating a GKE cluster in $GKE_LOC_REGION..."
	$EXE_GCLOUD container clusters create "$GKE_CLUSTER" \
		--num-nodes "$GKE_CLUSTER_NUM_NODES" --preemptible \
		--machine-type "$GKE_CLUSTER_MACHINE_TYPE" \
		--region "$GKE_LOC_REGION" \
		--enable-ip-alias \
		--enable-autorepair --enable-autoupgrade ||
		abort "could not create cluster $GKE_CLUSTER in $GKE_LOC_REGION"
	passed "... cluster $GKE_CLUSTER created"

	info "Getting credentials for cluster $GKE_CLUSTER..."
	$EXE_GCLOUD container clusters get-credentials --region "$GKE_LOC_REGION" "$GKE_CLUSTER" ||
		abort "could not get crfedentials for cluster $GKE_CLUSTER"
	passed "... credentials obtained"

	info "Doing a quick sanity check on that cluster $GKE_CLUSTER..."
	kubectl -n default get service kubernetes ||
		abort "GKE was not able to create a valid kubernetes cluster"
	passed "... cluster seems to be alive"

	info "GKE cluster created"
	;;

delete)
	gke_active_account || gke_login

	if [ -n "$CLUSTER_REUSE" ]; then
		info "cluster will not be deleted: CLUSTER_REUSE=true: exitting"
		exit 0
	fi

	if gke_exists_cluster; then
		info "Deleting cluster $GKE_CLUSTER"
		$EXE_GCLOUD container clusters delete --quiet \
			--region "$GKE_LOC_REGION" "$GKE_CLUSTER" ||
			abort "could not delete cluster $GKE_CLUSTER"
	fi

	gke_logout || warn "could not logout"
	;;

#
# return True if the cluster exists
#
exists)
	gke_active_account || gke_login
	gke_exists_cluster
	;;

#
# the registry
#
create-registry)
	info "Nothing to do for creating the registry in GKE"
	;;

delete-registry)
	info "Nothing to do for removing the registry in GKE"
	;;

#
# get the environment vars
#
get-env)
	echo "DEV_KUBECONFIG=$GKE_KUBECONFIG"
	echo "KUBECONFIG=$GKE_KUBECONFIG"
	echo "DEV_REGISTRY=$(gke_docker_registry)"

	echo "CLUSTER_NAME=$GKE_CLUSTER"
	echo "CLUSTER_SIZE=$GKE_CLUSTER_NUM_NODES"
	echo "CLUSTER_MACHINE=$GKE_CLUSTER_MACHINE_TYPE"
	echo "CLUSTER_REGION=$GKE_LOC_REGION"

	# GKE-specific variables
	echo "GKE_CLUSTER=$GKE_CLUSTER"
	echo "GKE_CLUSTER_NUM_NODES=$GKE_CLUSTER_NUM_NODES"
	echo "GKE_CLUSTER_MACHINE_TYPE=$GKE_CLUSTER_MACHINE_TYPE"
	echo "GKE_LOC_REGION=$GKE_LOC_REGION"
	echo "GKE_AUTH_FILE=$GKE_AUTH_FILE"
	;;

*)
	info "'$1' ignored for $CLUSTER_PROVIDER"
	;;

esac
