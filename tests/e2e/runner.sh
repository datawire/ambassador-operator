#!/usr/bin/env bash

runner_sh_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$runner_sh_dir" ] || {
	echo "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}

TOP_DIR="$runner_sh_dir/../.."

# shellcheck source=../../ci/infra/providers.sh
source "$TOP_DIR/ci/infra/providers.sh"

# shellcheck source=common.sh
source "$runner_sh_dir/common.sh"

########################################################################################################################

# keep the cluster after a failure
KEEP="${CLUSTER_KEEP:-}"

# resuse the cluster, just remove the testing namespace
REUSE="${CLUSTER_REUSE:-}"

# run verbose
VERBOSE=${VERBOSE:-}

########################################################################################################################
# setup dependencies
########################################################################################################################

setup() {
	info "Setting up the e2e runner dependencies"
}

cleanup() {
	info "Cleaning up any e2e runner dependencies"
}

########################################################################################################################
# build
########################################################################################################################

image_build() {
	info "Building image"
	make -C "$TOP_DIR" image-build
}

image_push() {
	local full_image=$(get_full_image_name)
	info "Pushing $AMB_OPER_IMAGE_NAME:$AMB_OPER_IMAGE_TAG -> $full_image"
	docker tag "$AMB_OPER_IMAGE_NAME:$AMB_OPER_IMAGE_TAG" "$full_image"
	docker push "$full_image"
}

########################################################################################################################
# tests
########################################################################################################################

env_create() {
	local must_create=1

	if [ -n "$REUSE" ]; then
		info "(reusing clusters in $CLUSTER_PROVIDER)"
		# check if a cluster is already running
		cluster_provider 'exists'
		if [ $? -eq 0 ]; then
			info "Cluster seems to exists and we are reusing clusters: will not recreate..."
			must_create=
		fi
	fi

	if [ -n "$must_create" ]; then
		cluster_provider 'create' || return 1
		cluster_provider 'create-registry' || return 1
	fi

	eval "$(cluster_provider 'get-env')"
	info "Environment obtained from $CLUSTER_PROVIDER:"
	info "... KUBECONFIG=$KUBECONFIG"
	info "... DEV_KUBECONFIG=$DEV_KUBECONFIG"
	info "... DEV_REGISTRY=$DEV_REGISTRY"
	info "... DOCKER_NETWORK=$DOCKER_NETWORK"
	info "... OPERATOR_IMAGE=$(get_full_image_name)"
	info "... CLUSTER_NAME=$CLUSTER_NAME"
	info "... CLUSTER_SIZE=$CLUSTER_SIZE"
	info "... CLUSTER_MACHINE=$CLUSTER_MACHINE"
	info "... CLUSTER_REGION=$CLUSTER_REGION"
	export KUBECONFIG DEV_KUBECONFIG DEV_REGISTRY DOCKER_NETWORK
	export CLUSTER_NAME CLUSTER_SIZE CLUSTER_MACHINE CLUSTER_REGION

	info "making sure the $TEST_NAMESPACE exists in the $CLUSTER_PROVIDER environment"
	kubectl create namespace "$TEST_NAMESPACE" 2>/dev/null || /bin/true
}

env_destroy() {
	if [ -n "$REUSE" ]; then
		info "Reusing clusters: removing operator"
		oper_uninstall "$TEST_NAMESPACE"
		passed "... operator removed"
	elif [ -n "$KEEP" ]; then
		info "Keeping the $CLUSTER_PROVIDER cluster alive"
	else
		info "Destroying the $CLUSTER_PROVIDER environment"
		cluster_provider 'delete'
	fi
}

get_test_filename() {
	local maybe_test="$1"
	if [ -f $maybe_test ]; then
		realpath "$maybe_test"
	elif [ -f "${TESTSUITES_DIR}/${maybe_test}" ]; then
		realpath ""${TESTSUITES_DIR}/${maybe_test}""
	elif [ -f "${TESTSUITES_DIR}/${maybe_test}.sh" ]; then
		realpath "${TESTSUITES_DIR}/${maybe_test}.sh"
	else
		echo ""
	fi
}

check() {
	if [ $# -eq 0 ]; then
		tests=$(ls $TESTSUITES_DIR/[0-9]*-*.sh)
	else
		tests=$@
	fi

	local rc=0
	info "Running tests with $CLUSTER_PROVIDER"
	for maybe_runner in $tests; do
		test_runner=$(get_test_filename $maybe_runner)
		[ -n "$test_runner" ] || abort "test script $maybe_runner not found"
		[ -f "$test_runner" ] || abort "test script $test_runner not found"
		[ -x "$test_runner" ] || {
			info "$test_runner is not executable: skipping..."
			continue
		}

		hl && info "Running $test_runner" && hl

		info "Preparing a $CLUSTER_PROVIDER environment..."
		if env_create; then
			passed "... environment created"
		else
			warn "failed to create environment: aborting..."
			break
		fi

		info "Checking registry..."
		if check_registry; then
			passed "... the registry seems fine"
		else
			warn "registry check failed: aborting..."
			break
		fi

		info "Checking kubeconfig..."
		if check_kubeconfig; then
			passed "... kubeconfig=$KUBECONFIG seem fine"
		else
			warn "kubeconfig $KUBECONFIG cluster check failed: aborting..."
			break
		fi

		# push the image and run the test script
		image_push || return 1
		"$test_runner"
		rc=$?

		info "Destroying environment..."
		if env_destroy; then
			passed "... environment destroyed"
		else
			warn "failed to destroy environment"
			break
		fi
		[ "$rc" -eq 0 ] || break
	done

	[ -n "$KEEP" ] || cluster_provider 'cleanup'
	return $rc
}

########################################################################################################################
# main
########################################################################################################################

cluster_providers="$(ls_cluster_providers)"

read -r -d '' HELP_MSG <<EOF
runner.sh [OPTIONS...] [COMMAND...]

where OPTION can be (note: some values can also be provided with the 'env:' environment variables):

  --kubeconfig <FILE>       specify the kubeconfig file (env:DEV_KUBECONFIG)
  --registry <ADDR:PORT>    specify the registry for the Ambassador image (env:DEV_REGISTRY)
  --image-name <NAME>       the image name
  --image-tag <TAG>         the image tag
  --cluster-provider <PRV>  the cluster provider to use (available: $cluster_providers) (env:CLUSTER_PROVIDER)
  --keep                    keep the cluster after a failure (env:CLUSTER_KEEP)
  --reuse                   reuse the cluster between tests (remove the namespace) (env:CLUSTER_REUSE)
  --debug                   debug the shell script
  --verbose                 log more message to output
  --help                    show this message

and COMMAND can be:
  build                     builds and pushes the image to the DEV_REGISTRY
  push                      (same as 'build')
  check [TEST ...]          run all tests (or some given test script)

Example:

  $ # build, push and perform some basic checks
  $ runner.sh --cluster-provider=k3d build check
EOF

FORCE=0

while [[ $# -gt 0 ]] && [[ "$1" == "--"* ]]; do
	opt="$1"
	shift #expose next argument
	case "$opt" in
	"--")
		break 2
		;;

		# the kubeconfig
	"--kubeconfig")
		export DEV_KUBECONFIG="$1"
		shift
		;;
	"--kubeconfig="*)
		export DEV_KUBECONFIG="${opt#*=}"
		;;

		# the registry
	"--registry")
		export DEV_REGISTRY="$1"
		shift
		;;
	"--registry="*)
		export DEV_REGISTRY="${opt#*=}"
		;;

		# the hostname
	"--hostname" | "--host" | "--address" | "--addr")
		export AMB_EXT_ADDR="$1"
		shift
		;;
	"--hostname="* | "--host="* | "--address="* | "--addr="*)
		export AMB_EXT_ADDR="${opt#*=}"
		;;

		# the image name
	"--image-name")
		export IMAGE_NAME="$1"
		shift
		;;
	"--image-name="*)
		export IMAGE_NAME="${opt#*=}"
		;;

		# the image tag
	"--image-tag")
		export IMAGE_TAG="$1"
		shift
		;;
	"--image-tag="*)
		export IMAGE_TAG="${opt#*=}"
		;;

		# the cluster provider
	"--cluster-provider")
		export CLUSTER_PROVIDER="$1"
		shift
		;;
	"--cluster-provider="*)
		export CLUSTER_PROVIDER="${opt#*=}"
		;;

		# other things
	"--force")
		export FORCE=1
		;;

	"--keep")
		KEEP=1
		;;

	"--reuse")
		REUSE=1
		;;

	"--debug")
		set -x
		;;

	"--verbose" | "-v")
		VERBOSE=1
		;;

	"--help")
		echo "$HELP_MSG"
		exit 0
		;;

	*)
		break 2
		;;
	esac
done

if [ -z "$DEV_KUBECONFIG" ]; then
	export DEV_KUBECONFIG="$DEF_KUBECONFIG"
fi

if [ -z "$DEV_REGISTRY" ]; then
	export DEV_REGISTRY="$DEF_REGISTRY"
fi

if [ -z "$CLUSTER_PROVIDER" ]; then
	export CLUSTER_PROVIDER="$DEF_CLUSTER_PROVIDER"
fi

export VERBOSE

if [[ $# -eq 0 ]]; then
	check
else
	opt=$1
	shift

	case "$opt" in
	setup)
		setup
		;;

	cleanup)
		cleanup
		;;

	build | push)
		image_build && image_push
		;;

	check | check_all)
		image_build && check $@
		;;

	*)
		echo "$HELP_MSG"
		echo
		abort "Unknown command $opt"
		;;

	esac
fi
