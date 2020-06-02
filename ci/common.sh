#!/bin/bash

common_sh_dir="$(cd "$(dirname ${BASH_SOURCE[0]})" >/dev/null 2>&1 && pwd)"
[ -d "$common_sh_dir" ] || {
	echo "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}
TOP_DIR=$(realpath $common_sh_dir/..)

# shellcheck source=consts.sh
source "$common_sh_dir/consts.sh"

########################################################################################################################
# utils
########################################################################################################################

alias echo_on="{ set -x; }"
alias echo_off="{ set +x; } 2>/dev/null"

log() { printf >&2 ">>> $1\n"; }

hl() {
	local curr_cols=$(tput cols)
	local cols=${1:-$((curr_cols - 4))}
	printf '>>> %*s\n' "$cols" '' | tr ' ' '*'
}

info() { log "${BLU}$1${END}"; }
highlight() { log "${MGT}$1${END}"; }

failed() {
	if [ -z "$1" ]; then
		log "${RED}failed!!!${END}"
	else
		log "${RED}$1${END}"
	fi
	abort "test failed"
}

passed() {
	if [ -z "$1" ]; then
		log "${GRN}done!${END}"
	else
		log "${GRN}$1${END}"
	fi
}

bye() {
	log "${BLU}$1... exiting${END}"
	exit 0
}

warn() { log "${RED}!!! WARNING !!! $1 ${END}"; }

abort() {
	log "${RED}FATAL: $1${END}"
	exit 1
}

# get a timestamp (in seconds)
timestamp() {
	date '+%s'
}

timeout_from() {
	local start=$1
	local now=$(timestamp)
	test $now -gt $((start + DEF_WAIT_TIMEOUT))
}

# command_exists <cmd>
#
# return true if the command provided exsists
#
command_exists() {
	[ -x "$1" ] || command -v $1 >/dev/null 2>/dev/null
}

replace_env_file() {
	info "Replacing env in $1..."
	[ -f "$1" ] || abort "$1 does not exist"
	envsubst <"$1" >"$2"
}

# check_url <url>
#
# checks that url is responding to requests, with an optional error message
#
check_url() {
	command_exists curl || abort "curl is not installed"
	curl -L --silent -k --output /dev/null --fail "$1"
}

# get_httpcode_url <url>
#
# return tyhe HTTP code obtained when accessing some url
#
get_httpcode_url() {
	local url="$1"
	command_exists curl || abort "curl is not installed"
	curl -k -s -o /dev/null -w "%{http_code}" "$url"
}

check_http_code() {
	local url="$1"
	local exp_code="$2"
	get_httpcode_url "$url" | grep -q "$exp_code"
}

wait_until() {
	local start_time=$(timestamp)
	info "Waiting for $@"
	until timeout_from $start_time || eval "$@"; do
		info "... still waiting for condition"
		sleep 1
	done
	! timeout_from $start_time
}

# wait until an URL returns a specific HTTP code
wait_http_code() {
	local url="$1"
	local code="$2"
	wait_until check_http_code $url $code
}

# kill_background
#
# kill the background job
#
kill_background() {
	info "(Stopping background job)"
	kill $!
	wait $! 2>/dev/null
}

wait_url() {
	local url="$1"
	info "Waiting for $url (max $DEF_WAIT_TIMEOUT seconds)"
	wait_until check_url $url
}

# download_exe <exe> <url>
#
# download an executable from an URL
#
download_exe() {
	local exe="$1"
	local url="$2"

	if ! command_exists "$exe"; then
		mkdir -p "$(dirname $exe)"
		info "Installing $(basename $exe)..."
		curl -L -o "$exe" "$url"
		chmod +x "$exe"
	fi
}

all_shs_in() {
	local d="$1"
	echo $(for f in $d/*.sh; do echo "$(basename $f .sh)"; done) | tr "\n" " "
}

########################################################################################################################
# kubeutils
########################################################################################################################

_check_registry() {
	info "Checking the registry at $DEV_REGISTRY"
	docker pull alpine &&
		docker tag alpine $DEV_REGISTRY/alpine &&
		docker push $DEV_REGISTRY/alpine
}

check_registry() {
	# registries somethimes can fail, so retry
	wait_until _check_registry
}

check_kubeconfig() {
	local kc=$DEV_KUBECONFIG
	[ -z "$kc" ] && kc=$KUBECONFIG
	[ -n "$kc" ] || {
		warn "no kubeconfig specified on DEV_KUBECONFIG/KUBECONFIG"
		return 1
	}
	[ -f "$kc" ] || {
		warn "kubeconfig does not exist at $kc"
		return 1
	}
	kubectl --kubeconfig="$kc" cluster-info
}

wait_deploy() {
	local name="$1"
	shift

	local full_name="deployment"
	[ -n "$name" ] && full_name="deployment/$name"

	kubectl wait --for=condition=available --timeout=600s $@ $full_name
	[ $? -eq 0 ] && passed "... $full_name is ready!"
}

# wait_kubectl_is <value> <expression>: waits until "kubectl <expression>" returns the given <value>
wait_kubectl_is() {
	local expected="$1"
	shift

	local kubectl="$(basename $EXE_KUBECTL)"
	command_exists "$kubectl" || abort "no kubectl available in $EXE_KUBECTL"

	info "Waiting for kubectl $@ to return '$expected'"
	local start_time=$(timestamp)
	until timeout_from $start_time || [ "$($kubectl $@ 2>/dev/null)" = "$expected" ]; do
		info "... still waiting"
		sleep 1
	done
	[ "$($kubectl $@ 2>/dev/null)" = "$expected" ]
}

wait_kubectl_zero() {
	wait_kubectl_is '' "$@"
}

wait_missing() {
	wait_kubectl_zero "-o name get $@"
}

# wait_pod_running "<name|selector>": wait for a pod to be running
wait_pod_running() {
	wait_kubectl_is 'Running' "get pod $@ -o jsonpath='{.items[0].status.phase}'"
}

# wait_pod_missing "<name|selector>": wait for a pod to be missing
wait_pod_missing() {
	wait_missing "pod $@"
}

# wait_namespace_missing "<name>": wait for a namespace to be missing
wait_namespace_missing() {
	wait_missing "namespace $1"
}

########################################################################################################################
# ambasssador stuff
########################################################################################################################

# check we are getting the fallback page
check_url_fallback() {
	curl -L --silent -k "$1" | grep -q "installed the Ambassador Edge Stack"
}

# replace all the "ambassador:XXX" or "aes:XXX" images with the image provided
replace_amb_image() {
	local image_name="$1"
	sed -e 's|image:.*\/ambassador\:.*|image: "'$image_name'"|g' |
		sed -e 's|image:.*\/aes\:.*|image: "'$image_name'"|g'
}

get_amb_addr() {
	if [ -n "$AMB_EXT_ADDR" ]; then
		echo "$AMB_EXT_ADDR"
	else
		kubectl get $@ service ambassador \
			-o 'go-template={{range .status.loadBalancer.ingress}}{{print .ip "\n"}}{{end}}' 2>/dev/null
	fi
}

check_amb_has_addr() {
	test -n "$(get_amb_addr $@)"
}

# wait_amb_addr <KUBECTL_ARGS...>
# wait untils Ambassador has an address
wait_amb_addr() {
	wait_until check_amb_has_addr $@ || {
		warn "Timeout waiting for Ambassador's IP. Current services:"
		kubectl get services $@
		warn "Ambassador IP address: $(get_amb_addr $@)"
		return 1
	}
}

# wait_not_amb_addr <KUBECTL_ARGS...>
# wait untils Ambassador does not have an address
wait_not_amb_addr() {
	wait_until "! check_amb_has_addr $@" || {
		warn "Timeout waiting for Ambassador to NOT have an IP. Current services:"
		kubectl get services $@
		warn "Ambassador IP address: $(get_amb_addr $@)"
		return 1
	}
}

# kubectl_apply_host
#
# apply a Host entry for the external name defined in AMB_EXT_ADDR
#
kubectl_apply_host() {
	local hostname="$1"

	info "Installing Host for $hostname"
	cat <<EOF | kubectl apply -f -
apiVersion: getambassador.io/v2
kind: Host
metadata:
  annotations:
    aes_res_changed: 'true'
  name: default-host
spec:
  hostname: '$hostname'
  selector:
    matchLabels:
      hostname: '$hostname'
  tlsSecret:
    name: '$hostname'
EOF
}

# get_amb_hosts
#
# get the names of the hosts.getambassador.io in the cluster
#
get_amb_hosts() {
	kubectl get hosts.getambassador.io --all-namespaces --output=jsonpath='{.items..metadata.name}'
}

amb_maybe_create_host() {
	local address="$1"
	local curr_hosts="$(get_amb_hosts)"

	if [ -z "$curr_hosts" ]; then
		info "No current Host: creating one"
		kubectl_apply_host "$address"
	else
		info "Current list of Hosts:"
		kubectl get hosts.getambassador.io --all-namespaces
	fi
}

amb_login() {
	info "Login into the Dashboard"
	edgectl login --namespace=$AMB_NAMESPACE "$(get_amb_addr)"
}

# amb_add_tlscontext
#
# Create an Ambassador TLSContext
#
amb_add_tlscontext() {
	info "Creating TLSContext"
	openssl genrsa -out key.pem 2048
	openssl req -x509 -key key.pem -out cert.pem -days 365 -subj '/CN=ambassador-cert' -new
	kubectl create secret tls tls-cert --cert=cert.pem --key=key.pem
	kubectl apply -f - <<EOF
apiVersion: getambassador.io/v1
kind: TLSContext
metadata:
  name: tls
spec:
  hosts: ["*"]
  secret: tls-cert
EOF
	rm -f key.pem cert.pem
}

########################################################################################################################
# cluster testing tools and demos
########################################################################################################################

HTTPBIN_REDIRECT_MANIFEST=$(
	cat <<EOF
---
apiVersion: getambassador.io/v1
kind: Mapping
metadata:
  name: httpbin
spec:
  prefix: /httpbin/
  service: httpbin.org
  host_rewrite: httpbin.org
EOF
)

QOTM_MANIFEST=$(
	cat <<EOF
---
apiVersion: v1
kind: Service
metadata:
 name: quote
spec:
 ports:
 - name: http
   port: 80
   targetPort: 8080
 selector:
   app: quote
---
apiVersion: apps/v1
kind: Deployment
metadata:
 name: quote
spec:
 replicas: 1
 selector:
   matchLabels:
     app: quote
 strategy:
   type: RollingUpdate
 template:
   metadata:
     labels:
       app: quote
   spec:
     containers:
     - name: backend
       image: quay.io/datawire/quote:0.2.7
       ports:
       - name: http
         containerPort: 8080
---
apiVersion: getambassador.io/v2
kind: Mapping
metadata:
 name: quote-backend
spec:
 prefix: /qotm/
 service: quote
EOF
)

# install_httpbin_redirect
#
# install the HTTPBIN demo app
#
install_httpbin_redirect() {
	info "Installing httpbin redirection manifest"
	echo "$HTTPBIN_REDIRECT_MANIFEST" | kubectl apply -f - && passed
}

# check_httpbin_mapping
#
# check if the HTTPBIN is ready and returning a valid response
#
check_httpbin_mapping() {
	local url="$1/httpbin/ip"

	info "Waiting for the HTTPBIN at $url"
	wait_url $url || return 1
	res="$(curl -k -L --silent $url)"
	if [ $? -ne 0 ]; then
		warn "could not curl $url"
		return 1
	fi

	info "Checking we got a IP"
	echo "$res" | grep -q "origin"
	if [ $? -ne 0 ]; then
		warn "no 'origin' found in response from $url: $res"
		return 1
	fi
	return 0
}

# install_qotm
#
# install the QOTM demo app
#
install_qotm() {
	info "Installing qotm manifest"
	echo "$QOTM_MANIFEST" | kubectl apply -f - && passed
}

# check_qotm_mapping
#
# check if the QOTM is ready and returning a valid response
#
check_qotm_mapping() {
	local url="$1/qotm/"

	info "Waiting for QOTM at $url"
	wait_url $url || return 1

	res="$(curl -k -L --silent $url)"
	if [ $? -ne 0 ]; then
		warn "could not curl $url"
		return 1
	fi

	info "Checking we got a valid quote of the day"
	for comp in "server" "time" "quote"; do
		echo "$res" | grep -q "$comp"
		if [ $? -ne 0 ]; then
			warn "no '$comp' found in response from $url: $res"
			return 1
		fi
	done
	return 0
}

########################################################################################################################
# Test utils
#######################################################################################################################

list_pkg_dirs() {
	go list -f '{{.Dir}}' ./cmd/... ./pkg/... ./test/... ./internal/... | grep -v generated
}

list_files() {
	# pipeline is much faster than for loop
	list_pkg_dirs | xargs -I {} find {} -name '*.go' | grep -v generated
}

# trap_add code signal
#
# Prepends a command to a trap
# - 1st arg:  code to add
# - remaining args:  names of traps to modify
#
# Example:  trap_add 'echo "in trap DEBUG"' EXIT
#
# See: http://stackoverflow.com/questions/3338030/multiple-bash-traps-for-the-same-signal
#
trap_add() {
	trap_add_cmd=$1
	shift || abort "${FUNCNAME} usage error"
	new_cmd=
	for trap_add_name in "$@"; do
		# Grab the currently defined trap commands for this trap
		existing_cmd=$(trap -p "${trap_add_name}" | awk -F"'" '{print $2}')

		# Define default command
		[ -z "${existing_cmd}" ] && existing_cmd="echo exiting @ $(date) 1>&2"

		# Generate the new command
		new_cmd="${trap_add_cmd};${existing_cmd}"

		# Assign the test
		trap "${new_cmd}" "${trap_add_name}" ||
			abort "unable to add to trap ${trap_add_name}"
	done
}

# add_go_mod_replace adds a "replace" directive from $1 to $2 with an
# optional version version $3 to the current working directory's go.mod file.
add_go_mod_replace() {
	local from_path="${1:?first path in replace statement is required}"
	local to_path="${2:?second path in replace statement is required}"
	local version="${3:-}"

	if [[ ! -d $to_path && -z $version ]]; then
		echo "second replace path $to_path requires a version be set because it is not a directory"
		exit 1
	fi
	if [[ ! -e go.mod ]]; then
		echo "go.mod file not found in $(pwd)"
		exit 1
	fi

	# Check if a replace line already exists. If it does, remove. If not, append.
	if grep -q "${from_path} =>" go.mod; then
		sed -E -i 's|^.+'"${from_path} =>"'.+$||g' go.mod
	fi
	# Do not use "go mod edit" so formatting stays the same.
	local replace="replace ${from_path} => ${to_path}"
	if [[ -n $version ]]; then
		replace="$replace $version"
	fi
	echo "$replace" >>go.mod
}

########################################################################################################################
# Git
#######################################################################################################################

# latest_git_version
#
# latest_git_version returns the highest semantic version
# number found in the repository, with the form "vX.Y.Z".
# Version numbers not matching the semver release format
# are ignored.
#
latest_git_version() {
	git tag -l | egrep "${semver_regex}" | sort -V | tail -1
}

# print_git_tags
#
# print_git_tags prints all tags present in the git repository.
#
print_git_tags() {
	git_tags=$(git tag -l | sed 's|^|    |')
	if [[ -n $git_tags ]]; then
		info "Found git tags:"
		for tag in $git_tags; do
			info " - ${tag}"
		done
		info ""
	fi
}

# is_latest_tag <candidate>
#
# is_latest_tag returns whether the candidate tag matches
# the latest tag from the git repository, based on semver.
# To be the latest tag, the candidate must match the semver
# release format.
#
is_latest_tag() {
	local candidate="$1"
	shift || abort "${FUNCNAME} usage error"
	if ! [[ $candidate =~ $semver_regex ]]; then
		return 1
	fi

	local latest="$(latest_git_version)"
	[[ -z $latest || $candidate == "$latest" ]]
}

# get_image_tags <image_name>
#
# get_image_tags returns a list of tags that are eligible to be pushed.
# If an image name is passed as an argument, the full <name>:<tag> will
# be returned for each eligible tag. The criteria is:
#   1. Is TRAVIS_BRANCH set?                 => <image_name>:$TRAVIS_BRANCH
#   2. Is TRAVIS_TAG highest semver release? => <image_name>:latest
#
get_image_tags() {
	local image_name=$1
	[[ -n $image_name ]] && image_name="${image_name}:"

	# Tag `:$TRAVIS_BRANCH` if it is set.
	# Note that if the build is for a tag, $TRAVIS_BRANCH is set
	# to the tag, so this works in both cases
	if [[ -n $TRAVIS_BRANCH ]]; then
		echo "${image_name}${TRAVIS_BRANCH}"
	fi

	# Tag `:latest` if $TRAVIS_TAG is the highest semver tag found in
	# the repository.
	if is_latest_tag "$TRAVIS_TAG"; then
		echo "${image_name}latest"
	fi
}

########################################################################################################################
# Images utils
#######################################################################################################################

semver_regex="^v(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$"

# docker_login <image_name>
#
# docker_login performs a docker login for the server of the provided
# image if the DOCKER_USERNAME and DOCKER_PASSWORD environment variables
# are set.
#
docker_login() {
	local image_name="$1"
	shift || abort "${FUNCNAME} usage error"

	local server=$(docker_server_for_image $image_name)
	if [[ -n $DOCKER_USERNAME && -n $DOCKER_PASSWORD ]]; then
		echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin "$server"
	else
		info "(skipping login to $server: no DOCKER_USERNAME/DOCKER_PASSWORD provided)"
	fi
}

# check_can_push
#
# check_can_push performs various checks to determine whether images
# built from this commit should be pushed. It prints a message and
# returns a failure code if any check doesn't pass.
#
check_can_push() {
	if [[ $TRAVIS != "true" ]]; then
		info "Detected execution in a non-TravisCI environment. Skipping image push."
		return 1
	elif [[ $TRAVIS_EVENT_TYPE == "pull_request" ]]; then
		info "Detected pull request commit. Skipping image push"
		return 1
	elif [[ ! -f "$HOME/.docker/config.json" ]]; then
		info "Docker login credentials required to push. Skipping image push."
		return 1
	fi
}

# docker_server_for_image <image_name>
#
# docker_server_for_image returns the server component of the image
# name. If the image name does not contain a server component, an
# empty string is returned.
#
docker_server_for_image() {
	local image_name="$1"
	shift || abort "${FUNCNAME} usage error"
	IFS='/' read -r -a segments <<<"$image_name"
	if [[ ${#segments[@]} -ge "2" ]]; then
		echo "${segments[0]}"
	else
		echo ""
	fi
}

# get_image_name <image_name>
#
# return the image name part of a full image.
# ie: "registry.local:5000/mmm/something:1.1" -> "something"
#
get_image_name() {
	local image="$1"
	shift || abort "${FUNCNAME} usage error"
	basename "$image" | cut -d ":" -f1
}

# get_image_tag <image_name>
#
# return the image tag part of a full image.
# ie: "registry.local:5000/mmm/something:1.1" -> "1.1"
#
get_image_tag() {
	local image="$1"
	shift || abort "${FUNCNAME} usage error"
	basename "$image" | cut -d ":" -f2
}

# get_image_server_and_path <image_name>
#
# return the image server and path part of a full image.
# ie: "registry.local:5000/mmm/something:1.1" -> "registry.local:5000/mmm"
#
get_image_server_and_path() {
	local image="$1"
	shift || abort "${FUNCNAME} usage error"
	dirname "$image"
}

########################################################################################################################
# Ambassador deployments
########################################################################################################################

# version_gt <V1> <V2>
# return True if V1 is greater than V2 (according to the SemVer rules)
function version_gt() {
	test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"
}

# get the image in the Ambassador deployment (ie, "quay.io/datawire/aes:1.1.0")
amb_get_image() {
	kubectl get $@ deployment "$AMB_DEPLOY" -o=jsonpath='{$.spec.template.spec.containers[:1].image}' 2>/dev/null
}

# get the tag of the image in the Ambassador deployment (ie, "quay.io/datawire/aes:1.1.0" -> 1.1.0)
amb_get_image_tag() {
	echo "$(amb_get_image $@)" | rev | cut -d ":" -f1 | rev
}

# get the repository part of the image in the Ambassador deployment
# (ie, "quay.io/datawire/aes:1.1.0" -> quay.io/datawire/aes)
amb_get_image_repository() {
	echo "$(amb_get_image $@)" | rev | cut -d ":" -f2- | rev
}

# gte the list of pods of ambassador
amb_get_pods() {
	kubectl get pods $@ $AMB_POD_SELECTOR -o jsonpath='{.items[*].metadata.name}'
}

amb_get_pods_yaml() {
	kubectl get pods $@ $AMB_POD_SELECTOR -o jsonpath='{.items[*].metadata.name}' -o yaml
}

amb_describe() {
	kubectl describe $@ deployment ambassador
}

# amb_check_image_tag <TAG> <KUBECTL_ARGS...>
# check that the Ambassador image has tag <TAG>
amb_check_image_tag() {
	local expected_version="$1"
	shift

	local deployed_version=$(amb_get_image_tag $@)
	if [ -z "$deployed_version" ]; then
		warn "could not obtain the actual versions of Ambassador: it is empty"
		return 1
	fi
	info "Current Ambassador deployment: $deployed_version"
	if [ "$deployed_version" != "$expected_version" ]; then
		warn "expected ($expected_version) and actual ($deployed_version) versions of Ambassador do not match"
		return 1
	fi
	info "${deployed_version} matches the expected version (${expected_version})"
}

# amb_check_image_repository <REPO> <KUBECTL_ARGS...>
# check that the Ambassador image has repository <REPOSITORY>
amb_check_image_repository() {
	local expected_repo="$1"
	shift

	local deployed_repo=$(amb_get_image_repository $@)
	if [ -z "$deployed_repo" ]; then
		warn "could not obtain Ambassador repository: it is empty"
		return 1
	fi
	info "Current Ambassador deployment: $deployed_repo"
	if [ "$deployed_repo" != "$expected_repo" ]; then
		warn "expected ($expected_repo) and actual ($deployed_repo) Ambassador repository do not match"
		return 1
	fi
	info "${deployed_repo} matches the expected repository (${expected_repo})"
}

# amb_wait_image_tag <VERSION> <KUBECTL_ARGS...>
# wait until the Ambassador deployment has an image with the given tag
amb_wait_image_tag() {
	local version="$1"
	shift

	local i=0
	local timeout=$DEF_WAIT_TIMEOUT
	until [ "$(amb_get_image_tag $@)" = "$version" ] || [ $i -ge $timeout ]; do
		info "waiting for Ambassador to be using tag $version ($i secs elapsed)"
		i=$((i + 1))
		sleep 1
	done

	if [ $i -gt $timeout ]; then
		warn "Timeout waiting for Ambassador's tag. Current services:"
		kubectl get services
		abort "Ambassador did have the expected tag after $timeout seconds"
	fi
}

# amb_wait_image_tag_gt <V1> <KUBECTL_ARGS...>
# wait until the Ambassador deployment image has a tag that is greater than V1
amb_wait_image_tag_gt() {
	local version="$1"
	shift

	local i=0
	local timeout=$DEF_WAIT_TIMEOUT
	local curr_version="$(amb_get_image_tag $@)"
	until version_gt "$curr_version" "$version" || [ $i -ge $timeout ]; do
		info "waiting for Ambassador to be using tag > $version ($i secs elapsed)"
		i=$((i + 1))
		sleep 1
		curr_version="$(amb_get_image_tag $@)"
	done

	if [ $i -gt $timeout ]; then
		warn "Timeout waiting for Ambassador's tag. Current services:"
		kubectl get services
		abort "Ambassador did have the expected tag after $timeout seconds"
	fi
}

# amb_scale <REPLICAS> <KUBECTL_ARGS...>
# scale up/down the Ambassador deployment
amb_scale() {
	local num="$1"
	shift

	kubectl scale --replicas="$num" $@ "deployments/$AMB_DEPLOY"
}

# amb_scale <KUBECTL_ARGS...>
# scale down to 0 the Ambassador deployment
amb_scale_0() {
	amb_scale 0 $@ && wait_pod_missing "$@ $AMB_POD_SELECTOR"
}

# amb_restart <KUBECTL_ARGS...>
# restart the Ambassador deployment
amb_restart() {
	kubectl rollout restart $@ deployments "$AMB_DEPLOY"
	sleep 1
	wait_deploy "$AMB_DEPLOY" $@
}

########################################################################################################################
# AmbassadorInstallation
########################################################################################################################

# amb_inst_apply_version <VERSION> <KUBECTL_ARGS...>
# apply an `AmbassadorInstallation` with a `version`
amb_inst_apply_version() {
	local version="$1"
	shift

	info "Creating AmbassadorInstallation with version=${version}..."
	cat <<EOF | kubectl apply $@ -f -
apiVersion: getambassador.io/v2
kind: AmbassadorInstallation
metadata:
  name: ${AMB_INSTALLATION_NAME}
spec:
  version: "${version}"
  helmRepo: "${AMB_INSTALLATION_HELM_REPO}"
  logLevel: info
EOF
	passed "... AmbassadorInstallation created successfully..."
}

# apply_amb_inst_image <IMAGE> <KUBECTL_ARGS...>
# apply an `AmbassadorInstallation` with a `baseImage`
apply_amb_inst_image() {
	local image="$1"
	shift

	info "Creating an AmbassadorInstallation with baseImage=${image}..."
	cat <<EOF | kubectl apply $@ -f -
apiVersion: getambassador.io/v2
kind: AmbassadorInstallation
metadata:
  name: ${AMB_INSTALLATION_NAME}
spec:
  baseImage: ${image}
  logLevel: info
EOF
	passed "... AmbassadorInstallation created successfully..."
}

# apply_amb_inst_oss...>
# apply an `AmbassadorInstallation` with a `installOSS: true`
apply_amb_inst_oss() {
	info "Creating an AmbassadorInstallation with 'installOSS: true'..."
	cat <<EOF | kubectl apply $@ -f -
apiVersion: getambassador.io/v2
kind: AmbassadorInstallation
metadata:
  name: ${AMB_INSTALLATION_NAME}
spec:
  installOSS: true
  logLevel: info
EOF
	passed "... AmbassadorInstallation created successfully..."
}

# apply_amb_inst_aes...>
# apply an `AmbassadorInstallation` with a `installOSS: false`
apply_amb_inst_aes() {
	info "Creating an AmbassadorInstallation with 'installOSS: false'..."
	cat <<EOF | kubectl apply $@ -f -
apiVersion: getambassador.io/v2
kind: AmbassadorInstallation
metadata:
  name: ${AMB_INSTALLATION_NAME}
spec:
  installOSS: false
  logLevel: info
EOF
	passed "... AmbassadorInstallation created successfully..."
}

# kube_check_resource_empty "resource name" "kubectl args"
# check if a resource is present in Kubernetes
# returns 1 if exists, 0 if does not exist
kube_check_resource_empty() {
	local kube_resource="$1"
	shift

	info "Checking if Kubernetes resource $kube_resource exists"
	if [[ $(kubectl get "$kube_resource" $@ 2>/dev/null) ]]; then
		info "... Kubernetes resource $kube_resource exists"
		return 1
	else
		info "... Kubernetes resource $kube_resource does not exist"
		return 0
	fi
}

# amb_inst_delete <KUBECTL_ARGS...>
# delete an `AmbassadorInstallation`
amb_inst_delete() {
	lst=$(kubectl get $@ ambassadorinstallations --no-headers -o custom-columns=":metadata.name" 2>/dev/null)
	info "Removing all the AmbassadorInstallations: $lst"
	for k in $lst; do
		kubectl delete $KUBECTL_DELETE_ARGS $@ ambassadorinstallations "$k" || return 1
		wait_missing "$@ ambassadorinstallations $k" || return 1
		passed "... AmbassadorInstallation $k removed."
	done
	info "Current list of AmbassadorInstallations: " && kubectl get $@ ambassadorinstallations 2>/dev/null
	return 0
}

amb_inst_describe() {
	kubectl describe $@ ambassadorinstallations ${AMB_INSTALLATION_NAME}
}

amb_inst_check_success() {
	amb_inst_describe $@ | grep -E -q "(UpdateSuccessful|InstallSuccessful)" 2>/dev/null
}

amb_inst_check_uninstalled() {
	# NOTE: we cannot look at the AmbassadorInstallation because... it is gone! so we use the Operator logs
	oper_logs_dump $@ | grep -E -q "Uninstalled release" 2>/dev/null
}

########################################################################################################################
# Operator
########################################################################################################################

# 'cat' a manifest, replacing the default image (ie, ambassador-operator:dev)
# by the full image name (ie, docker.io/datawire/ambassador-operator:v1.2.3)
get_full_image_name() {
	if [ -n "$OPERATOR_IMAGE" ]; then
		echo "$OPERATOR_IMAGE"
	elif [ -n "$DEV_REGISTRY" ]; then
		echo "$DEV_REGISTRY/$AMB_OPER_IMAGE_NAME:$AMB_OPER_IMAGE_TAG"
	else
		echo "$AMB_OPER_IMAGE_NAME:$AMB_OPER_IMAGE_TAG"
	fi
}

# 'cat' a manifest, replacing the default image (ie, ambassador-operator:dev)
# by the full image name (ie, docker.io/datawire/ambassador-operator:v1.2.3)
cat_setting_image() {
	local full_image=$(get_full_image_name)
	info "(replacing image ${AMB_OPER_MANIF_DEF_IMAGE} by ${full_image})"
	cat "$1" | sed -e "s|$AMB_OPER_MANIF_DEF_IMAGE|$full_image|g"
}

# oper_uninstall <NS>
# uninstall the operator from the namespace <NS>
oper_uninstall() {
	local namespace="$1"
	shift

	[ -z "$DEV_REGISTRY" ] && abort "no DEV_REGISTRY defined"
	[ -z "$KUBECONFIG" ] && abort "no KUBECONFIG defined"

	amb_inst_delete -n "$namespace" || {
		oper_logs_dump -n "$namespace"
		abort "could not remove AmbassadorInstallations in namespace $namespace"
	}

	info "Removing the operator..."
	cat_setting_image "$AMB_OPER_MANIF" | kubectl delete $KUBECTL_DELETE_ARGS -n "$namespace" -f -
	for f in $AMB_OPER_CRDS "$AMB_OPER_MANIF"; do
		info "... removing $f"
		kubectl delete -n "$namespace" $KUBECTL_DELETE_ARGS -f $f || {
			oper_logs_dump -n "$namespace"
			abort "could not delete $f"
		}
	done

	# note: it is important have deleted all the AmbassadorInstallations at this point,
	#       otherwise the removal of the namespace will fail
	info "Removing namespace $namespace..."
	kubectl delete namespace $KUBECTL_DELETE_ARGS "$namespace" || abort "could not delete namespace $namespace"
	wait_namespace_missing "$namespace" || {
		oper_logs_dump -n "$namespace"
		kubectl get all -n "$namespace"
		abort "namespace $namespace still present"
	}
	passed "... namespace $namespace removed."
}

# oper_install <NS>
# install the operator in the namespace <NS>
oper_install() {
	if [ $# -eq 1 ]; then
		local method="yaml"
		local namespace="$1"
	else
		local method="$1"
		local namespace="$2"
	fi

	[ -z "$DEV_REGISTRY" ] && abort "no DEV_REGISTRY defined"
	[ -z "$KUBECONFIG" ] && abort "no KUBECONFIG defined"

	info "Creating test namespace $namespace..."
	kubectl create namespace "$namespace" 2>/dev/null || /bin/true

	info "================================="
	info "Deploying via $method"
	info "================================="
	case "$method" in
	"yaml" | "YAML" | "Yaml" | "manifest" | "manifests")
		oper_install_yaml "$namespace"
		;;
	"helm" | "Helm" | "HELM")
		oper_install_helm "$namespace"
		;;
	*)
		warn "Invalid Operator deployment method specified: $1"
		exit 1
		;;
	esac
	info "Waiting for the Operator deployment..."
	wait_deploy $AMB_OPER_DEPLOY -n "$namespace" || {
		oper_describe
		return 1
	}

	info "Reducing check/update frequency update=$AMB_OPER_UPDATE_INTERVAL/check=$AMB_OPER_CHECK_INTERVAL..."
	kubectl set env -n "$namespace" deployments "$AMB_OPER_DEPLOY" AMB_UPDATE_INTERVAL="$AMB_OPER_UPDATE_INTERVAL"
	kubectl set env -n "$namespace" deployments "$AMB_OPER_DEPLOY" AMB_CHECK_INTERVAL="$AMB_OPER_CHECK_INTERVAL"
	kubectl rollout restart -n "$namespace" deployments "$AMB_OPER_DEPLOY"
	sleep 1
	wait_deploy "$AMB_OPER_DEPLOY" -n "$namespace" || return 1
}

oper_install_yaml() {
	local namespace="$1"
	shift

	kubectl apply $KUBECTL_APPLY_ARGS -f $AMB_OPER_CRDS
	kubectl apply -n "$namespace" $KUBECTL_APPLY_ARGS -f "$AMB_OPER_MANIF"

	cat_setting_image "$AMB_OPER_MANIF" |
		sed -e "s/namespace: ambassador/namespace: $namespace/g" |
		kubectl apply -n "$namespace" $KUBECTL_APPLY_ARGS -f -
}

oper_install_helm() {
	local namespace="$1"
	helm install ambassador-operator --wait --namespace "$namespace" \
		--set namespace="$namespace",image.name=$(get_full_image_name) \
		deploy/helm/ambassador-operator/
}

oper_logs_dump() {
	kubectl logs $@ deployment/"$AMB_OPER_DEPLOY" --previous
	kubectl logs $@ deployment/"$AMB_OPER_DEPLOY"
}

oper_describe() {
	kubectl describe $@ deployment "$AMB_OPER_DEPLOY"
}

# wait until the operator has been deployed
oper_wait_install() {
	wait_deploy ambassador-operator $@ || return 1
	passed "... the Ambassador operator is alive"
}

oper_get_random_pod() {
	kubectl get pod $@ -l "name=ambassador-operator" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

_check_file_contains() {
	local file="$1"
	shift
	local pattern="$1"
	shift

	pod=$(oper_get_random_pod $@)
	if [ -n "$pod" ]; then
		res="$(kubectl exec -it $@ $pod -- cat $file 2>/dev/null)"
		if [ $? -eq 0 ] && [ -n "$res" ]; then
			echo "$res" | grep -q -E "$pattern" && return 0
		fi
	fi
	return 1
}

oper_check_file_contains() {
	wait_until _check_file_contains $@
}
