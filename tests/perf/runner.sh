#!/usr/bin/env bash

runner_sh_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$runner_sh_dir" ] || {
	echo "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}

TOP_DIR="$runner_sh_dir/../.."

# shellcheck source=../../ci/infra/providers.sh
source "$TOP_DIR/ci/infra/providers.sh"

user=$(whoami)
num="${TRAVIS_BUILD_ID:-0}"

########################################################################################################################

# the namespace for running tests
TEST_NAMESPACE="$AMB_NAMESPACE"

# arguments for the test
MAPPINGS_COUNT=${NUM_MAPPINGS:-10}
HOSTS_COUNT=${NUM_HOSTS:-1}
REPLICAS_COUNT=${NUM_REPLICAS:-1}

LATENCY_RATES=${LAT_RATES:-100}
LATENCY_DURATION="30s"
LATENCY_REPORTS_DIR="/tmp"

# the backend manifests
MANIF_BACKEND="$runner_sh_dir/manifests/backend.yaml"
BACKEND_NAMESPACE="default"

# some other manifests
MANIF_HOSTS="$runner_sh_dir/manifests/host.yaml"
MANIF_VEGETA="$runner_sh_dir/manifests/vegeta.yaml"

# calm down time before running the test
CALM_DOWN_TIME=30

# update and check intervals for the operator
# we don't need to use short intervals here
AMB_OPER_UPDATE_INTERVAL="12h"
AMB_OPER_CHECK_INTERVAL="5m"
export AMB_OPER_UPDATE_INTERVAL AMB_OPER_CHECK_INTERVAL

# Ambassador external address
AMB_EXT_ADDR=${AMB_EXT_ADDR:-}
export AMB_EXT_ADDR

# Ambassador version to install by the operator (leave empty for anything)
AMB_VERSION=""

# the cluster name for performance tests
CLUSTER_NAME="${CLUSTER_NAME:-amb-perf-tests-$user-$num}"
export CLUSTER_NAME

# the Go script for waiting for URLs
EXE_WAIT_MULTI_URL="$runner_sh_dir/scripts/wait-multi-url.go"

########################################################################################################################
# utils
########################################################################################################################
load_cluster_local_overrides() {
	local f="$runner_sh_dir/inc/${CLUSTER_PROVIDER}.sh"
	if [ -f "$f" ]; then
		info "Loading $f"
		source "$f"
	fi
	if [ -f "${f}.local" ]; then
		info "Loading (local file) ${f}.local"
		source "${f}.local"
	fi
}

# generate an initial `Host` that uses ACME (for enabling HTTPS)
gen_initial_host() {
	local hostname="$1"
	[ -n "$hostname" ] || abort "no hostname provided"
	cat "$MANIF_HOSTS" | sed -e "s/__HOSTNAME__/$hostname/g"
}

get_test_configuration_str() {
	echo "H$HOSTS_COUNT-M$MAPPINGS_COUNT-R$REPLICAS_COUNT"
}

get_cluster_machine_short() {
	echo "$1" | sed -e 's/Standard//g' | tr '_' '-'
}

########################################################################################################################
# benchmarks
########################################################################################################################

# see https://github.com/datawire/aes-loadtest/

wait_all_urls() {
	go run "$EXE_WAIT_MULTI_URL" $@
}

bench_cleanup() {
	info "Cleanup any previous scenario..."

	info "Scaling down Ambassador..."
	amb_scale 0 -n "$TEST_NAMESPACE"

	info "Removing previous mappings/hosts..."
	kubectl delete mappings -n default --selector=generated=true --wait=true
	kubectl delete hosts -n default --selector=generated=true --wait=true
	passed "... mappings/hosts removed."

	info "Removing vegeta..."
	kubectl delete --wait=true -f $MANIF_VEGETA
	passed "... vegeta removed."

	#info "Restarting Ambassador"
	#amb_restart -n "$TEST_NAMESPACE"

	info "Scaling up Ambassador to $REPLICAS_COUNT replicas..."
	amb_scale "$REPLICAS_COUNT" -n "$TEST_NAMESPACE"
}

bench_prepare() {
	local target="$1"
	local aes_host="$2"
	[ -n "$aes_host" ] || abort "no target provided"

	info "Configuration: $(get_test_configuration_str)"
	info "Target: http://$aes_host"

	info "Loading backend services (in default namespace)..."
	kubectl apply -n "$BACKEND_NAMESPACE" -f "$MANIF_BACKEND" || return 1
	wait_deploy "echo-a" || return 1
	wait_deploy "echo-b" || return 1

	info "Generating and applying $MAPPINGS_COUNT mappings without a backing upstream (void)"
	./scripts/mappings.py --count "$MAPPINGS_COUNT" --target "$target" |
		kubectl apply -f - || abort "could not create mappings"
	passed "... $MAPPINGS_COUNT mappings applied."

	info "Generating an initial host for $aes_host (for enabling HTTPS)"
	gen_initial_host "$aes_host" | kubectl apply -f - || abort "could not create hosts"

	info "Generating and applying $HOSTS_COUNT hosts"
	./scripts/hosts.py --count "$HOSTS_COUNT" --hostname "$aes_host" |
		kubectl apply -f - || abort "could not create hosts"
	passed "... $HOSTS_COUNT hosts applied."
}

bench_reconf_latency() {
	local aes_host="$1"
	[ -n "$aes_host" ] || abort "no target provided"
	local what="reconfiguration latency - $CLUSTER_MACHINE / $(get_test_configuration_str)"

	info "***********************************************************************************************"
	info "*** Benchmarking $what ***"
	info "***********************************************************************************************"
	info "objective: how long does it take for an update to a single mapping to go live"
	bench_prepare "void" "$aes_host"

	local url="https://$aes_host/echo-$MAPPINGS_COUNT/"
	local url_expr="https://$aes_host/echo-@/"

	info "Wait a bit for ALL the mappings to be applied and configured (waiting for $url_expr)..."
	info "(HTTP code will be 503: loaded but with an 'void' backend)"
	wait_all_urls --url "$url_expr" --start 1 --end "$MAPPINGS_COUNT" --wait-code 503 || return 1
	passed "... $url_expr all unavailable: good"

	info "Sleeping for $CALM_DOWN_TIME secs until the system calms down..." && sleep $CALM_DOWN_TIME
	info "Changing mapping $MAPPINGS_COUNT to 'echo-a' and waiting for $url to return 200"
	./scripts/mappings.py \
		--id "$MAPPINGS_COUNT" \
		--target "echo-a.$BACKEND_NAMESPACE" \
		-n "$BACKEND_NAMESPACE" |
		kubectl apply -f - &&
		wait_all_urls --url "$url" \
			--wait-code 200 \
			--reason "$what" || return 1

	passed "***********************************************************************************************"
	passed "$what: see the 'Elapsed time' above ^^^"
	passed "***********************************************************************************************"
}

bench_reconf_throu() {
	local aes_host="$1"
	[ -n "$aes_host" ] || abort "no target provided"
	local what="reconfiguration throughput - $CLUSTER_MACHINE / $(get_test_configuration_str)"

	info "***********************************************************************************************"
	info "*** Benchmarking $what ***"
	info "***********************************************************************************************"
	info "objective: do a batch update of all mappings and measuring how long it takes till all updates are live"
	bench_prepare "void" "$aes_host"

	local url_expr="https://$aes_host/echo-@/"

	info "Wait a bit for mappings to be applied and configured (waiting for $url_expr)..."
	info "(HTTP code will be 503: loaded but with an 'void' backend)"
	wait_all_urls --url "$url_expr" --start 1 --end "$MAPPINGS_COUNT" --wait-code 503 || return 1
	passed "... $url_expr all unavailable: good"

	info "Sleeping for $CALM_DOWN_TIME secs until the system calms down..." && sleep $CALM_DOWN_TIME
	info "Changing all $MAPPINGS_COUNT mappings to 'echo-a' and waiting for $url_expr to return 200"
	./scripts/mappings.py \
		--count "$MAPPINGS_COUNT" \
		--target "echo-a.$BACKEND_NAMESPACE" \
		-n "$BACKEND_NAMESPACE" |
		kubectl apply -f - &&
		wait_all_urls --url "$url_expr" \
			--start 1 --end "$MAPPINGS_COUNT" \
			--wait-code 200 \
			--reason "$what" || return 1

	passed "***********************************************************************************************"
	passed "$what: see the 'Elapsed time' above ^^^"
	passed "***********************************************************************************************"
}

bench_pod_spinup() {
	local aes_host="$1"
	[ -n "$aes_host" ] || abort "no target provided"
	local what="pod spinup - $CLUSTER_MACHINE / $(get_test_configuration_str)"

	info "***********************************************************************************************"
	info "*** Benchmarking $what ***"
	info "***********************************************************************************************"
	info "objective: how long does it take for a fresh pod to become ready..."
	bench_prepare "echo-a.$BACKEND_NAMESPACE" "$aes_host"

	local url="https://$aes_host/echo-$MAPPINGS_COUNT/"

	wait_all_urls --url "$url" --wait-code 200 || return 1
	passed "... $url is available"

	info "Scale DOWN the AES deployment to 0: $url should stop working..."
	amb_scale_0 -n "$TEST_NAMESPACE" && wait_all_urls --url "$url" --wait-error || abort "pods still running"

	info "Sleeping for $CALM_DOWN_TIME secs until the system calms down..." && sleep $CALM_DOWN_TIME
	info "Scaling UP the AES deployment to $REPLICAS_COUNT and waiting for $url to become available".
	amb_scale "$REPLICAS_COUNT" -n "$TEST_NAMESPACE" &&
		wait_all_urls --url "$url" --wait-code 200 \
			--reason "$what" || return 1

	passed "***********************************************************************************************"
	passed "$what: see the 'Elapsed time' above ^^^"
	passed "***********************************************************************************************"
}

bench_latency() {
	local aes_host="$1"
	[ -n "$aes_host" ] || abort "no target provided"
	local what="latency - $CLUSTER_MACHINE / $(get_test_configuration_str)"

	mkdir -p "$LATENCY_REPORTS_DIR" || abort "could not create reports dir $LATENCY_REPORTS_DIR"

	info "***********************************************************************************************"
	info "*** Benchmarking $what ***"
	info "***********************************************************************************************"
	info "objective: latency in connections..."

	MAPPINGS_COUNT=1 HOSTS_COUNT=1 bench_prepare "echo-a.$BACKEND_NAMESPACE" "$aes_host"

	local url="https://$aes_host/echo-1/"

	info "Enabling endpoint routing..."
	cat <<EOF | kubectl apply -f -
---
apiVersion: getambassador.io/v2
kind: KubernetesEndpointResolver
metadata:
  name: endpoint
EOF

	info "Checking $url is available..."
	wait_all_urls --url "$url" --wait-code 200 || return 1
	passed "... $url is available"

	info "Scale DOWN the AES deployment to 0..."
	amb_scale 0 -n "$TEST_NAMESPACE" || abort "pods still running"

	info "Deploying vegeta..."
	kubectl apply -n "$TEST_NAMESPACE" -f "$MANIF_VEGETA" || abort "pods still running"
	wait_deploy "vegeta" -n "$TEST_NAMESPACE"
	passed "... vegeta deployed"

	info "Scaling UP the AES deployment to $REPLICAS_COUNT and waiting for $url to become available".
	amb_scale "$REPLICAS_COUNT" -n "$TEST_NAMESPACE" &&
		wait_all_urls --url "$url" --wait-code 200 || return 1

	info "Getting the list of Vegeta pods:"
	local vegeta_pods=$(kubectl get pods --all-namespaces -l app=vegeta -o jsonpath='{.items[*].metadata.name}')
	local a_vegeta_pod="${vegeta_pods%% *}"
	passed "... pods: $vegeta_pods"
	[ -n "$a_vegeta_pod" ] || abort "no vegeta pod could be obtained."

	info "Running vegeta in pod $a_vegeta_pod..."
	for rate in $(echo $LATENCY_RATES | tr "," " "); do
		machine_short="$(get_cluster_machine_short $CLUSTER_MACHINE)"
		local_report="$LATENCY_REPORTS_DIR/results-${rate}-${machine_short}.html"
		remote_bin="/tmp/results-${rate}-${machine_short}.bin"
		remote_report="/tmp/results-${rate}-${machine_short}.html"
		report_title="Latency report: $LATENCY_DURATION @ $rate RPS ($CLUSTER_MACHINE machines)"

		info "... sending requests at $rate rps for $LATENCY_DURATION"
		kubectl exec -n "$TEST_NAMESPACE" -ti "$a_vegeta_pod" -- \
			sh -c "echo 'GET $url' | vegeta attack -insecure -rate=$rate -duration=$LATENCY_DURATION | tee $remote_bin | vegeta report"

		info "... generating and copying HTML file to $local_report"
		kubectl exec -n "$TEST_NAMESPACE" -ti "$a_vegeta_pod" -- \
			sh -c "cat $remote_bin | vegeta plot --title '$report_title' > $remote_report"
		rm -f "$local_report" || /bin/true
		kubectl cp "$TEST_NAMESPACE/$a_vegeta_pod:$remote_report" "$local_report"

		local what="latency - $CLUSTER_MACHINE / $(get_test_configuration_str) / $rate RPS for $LATENCY_DURATION"

		passed "***********************************************************************************************"
		passed "$what: report saved at:"
		passed "       file://$local_report"
		passed "***********************************************************************************************"
	done
	info "... done."
}

# run benchmarks
bench() {
	local what="$1"

	get_env
	local addr=$(get_amb_addr -n "$TEST_NAMESPACE")
	[ -n "$addr" ] || abort "could not obtain the Ambassador address. Try to force one with --addr <ADDRESS>."

	case "$what" in
	"reconfigure-latency" | "reconfig-latency" | "reconf-latency" | "rlatency")
		bench_cleanup && bench_reconf_latency "$addr" || return 1
		;;

	"reconfigure-throu" | "reconfig-throu" | "reconf-throu" | "throu")
		bench_cleanup && bench_reconf_throu "$addr" || return 1
		;;

	"pod-spinup" | "spinup")
		bench_cleanup && bench_pod_spinup "$addr" || return 1
		;;

	"latency" | "lat")
		bench_cleanup && bench_latency "$addr" || return 1
		;;

	"cleanup")
		bench_cleanup
		;;

	"all")
		for i in "reconfigure-latency" "reconfigure-throu" "pod-spinup"; do
			bench "$i" || return 1
		done
		;;

	*)
		abort "Don't kow how to benchmark $what"
		;;
	esac
}

########################################################################################################################
# build
########################################################################################################################

get_env() {
	eval "$(cluster_provider 'get-env' 2>/dev/null)"
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
}

image_build() {
	info "Building image"
	make -C "$TOP_DIR" image-build || return 1
}

image_push() {
	[ -n "$DEV_REGISTRY" ] || abort "no registry provided in DEV_REGISTRY"
	local full_image=$(get_full_image_name)
	info "Pushing $AMB_OPER_IMAGE_NAME:$AMB_OPER_IMAGE_TAG -> $full_image"
	docker tag "$AMB_OPER_IMAGE_NAME:$AMB_OPER_IMAGE_TAG" "$full_image" || return 1
	docker push "$full_image" || return 1
}

deploy() {
	local what=$1
	[ -z "$what" ] && what="ambassador"

	case "$what" in
	"operator")
		get_env || return 1
		image_build || return 1
		image_push || return 1
		oper_install "yaml" "$TEST_NAMESPACE" || return 1
		oper_wait_install -n "$TEST_NAMESPACE" || return 1
		;;

	"ambassador")
		deploy "operator" || return 1
		amb_inst_apply_version "$AMB_VERSION" -n "$TEST_NAMESPACE" || return 1

		info "Waiting for the Operator to install Ambassador"
		if ! wait_amb_addr -n "$TEST_NAMESPACE"; then
			[ -n "$VERBOSE" ] && oper_logs_dump -n "$TEST_NAMESPACE"
			failed "could not get an Ambassador IP"
		fi
		passed "... good! Ambassador has been installed by the Operator!"

		[ -n "$VERBOSE" ] && info "Describe: Ambassador Operator deployment:" && oper_describe -n "$TEST_NAMESPACE"
		[ -n "$VERBOSE" ] && info "Describe: Ambassador deployment:" && amb_describe -n "$TEST_NAMESPACE"
		info ""
		local addr=$(get_amb_addr -n "$TEST_NAMESPACE")
		info "Ambassador is available at $addr"
		;;

	*)
		abort "Don't kow how to deploy $what"
		;;
	esac
}

########################################################################################################################
# performance tests
########################################################################################################################

setup() {
	info "Creating environment with $CLUSTER_PROVIDER..."
	cluster_provider 'create' || return 1
	cluster_provider 'create-registry' || return 1
	get_env || return 1
	[ -n "$DEV_REGISTRY" ] || abort "no registry obtained in DEV_REGISTRY"
	[ -f "$KUBECONFIG" ] || abort "no kubeconfig obtained in KUBECONFIG"
	check_kubeconfig || abort "no valid kubeconfig from KUBECONFIG"
	check_registry || abort "no valid registry  at DEV_REGISTRY"
}

cleanup() {
	info "Cleaning up environment with $CLUSTER_PROVIDER..."
	cluster_provider 'delete-registry' || return 1
	cluster_provider 'delete' || return 1
}

run() {
	eval "$(cluster_provider 'get-env')"
	info "Environment obtained from $CLUSTER_PROVIDER:"
	info "... KUBECONFIG=$KUBECONFIG"
	info "... DEV_KUBECONFIG=$DEV_KUBECONFIG"
	info "... DEV_REGISTRY=$DEV_REGISTRY"
	info "... DOCKER_NETWORK=$DOCKER_NETWORK"
	info "... OPERATOR_IMAGE=$(get_full_image_name)"

	export KUBECONFIG DEV_KUBECONFIG DEV_REGISTRY DOCKER_NETWORK
}

########################################################################################################################
# main
########################################################################################################################

cluster_providers="$(ls_cluster_providers)"

read -r -d '' HELP_MSG <<EOF
runner.sh [OPTIONS...] [COMMAND...]

where OPTION can be (note: some values can also be provided with the 'env:' environment variables):

  --kubeconfig <FILE>       specify the kubeconfig file
                            (def:from cluster provider) (env:DEV_KUBECONFIG)
  --registry <ADDR:PORT>    specify the registry for the Ambassador image
                            (def:from cluster provider) (env:DEV_REGISTRY)
  --image-name <NAME>       the image name (def:$AMB_OPER_IMAGE_NAME)
  --image-tag <TAG>         the image tag (def:$AMB_OPER_IMAGE_TAG)
  --amb-version <VERSION>   the version of Ambassador to install (def:$AMB_VERSION)

cluster parameters:

  --cluster-provider <PRV>  the cluster provider to use
                            (available: $cluster_providers) (def:$CLUSTER_PROVIDER) (env:CLUSTER_PROVIDER)
  --cluster-name <NAME>     cluster provider: name (def: $CLUSTER_NAME)
  --cluster-size <SIZE>     cluster provider: number of nodes
  --cluster-machine <NAME>  cluster provider: machine size/model
  --cluster-region <NAME>   cluster provider: region
  --cluster-reuse           reuse the cluster

benchmarks runner:

  --addr <ADDR>             force an IP/DNS for Ambassador (def:$AMB_EXT_ADDR) (env:AMB_EXT_ADDR)
  --num-mappings <NUM>      number of mappings (def:$MAPPINGS_COUNT) (env:NUM_MAPPINGS)
  --num-hosts <NUM>         number of hosts (def:$HOSTS_COUNT) (env:NUM_HOSTS)
  --num-replicas <NUM>      number of replicas (def:$REPLICAS_COUNT) (env:NUM_REPLICAS)
  --latency-rates <RATES>   comma-separted list of rates to test
  --latency-duration <DUR>  latency benchmark duration (ie, '2m', '30s', etc)

extra flags:

  --keep                    keep the cluster after a failure (env:CLUSTER_KEEP)
  --debug                   debug the shell script
  --help                    show this message

and 'COMMAND' can be:

  setup                     creates a cluster
  cleanup                   destroy the cluster
  env                       dump the environment (you can do 'eval \$($0 env)')
  batch                     run benchmarks in batch mode
  deploy <SUBCOMMAND>
  bench <SUBCOMMAND>

and 'deploy SUBCOMMAND' can be:

  operator                  deploy the operator
  ambassador                create a 'AmbassadorInstallation' and wait for the operator to install Ambassador

and 'bench SUBCOMMAND' can be:

  reconf-latency            benchmark reconfiguration latency
  reconf-throu              benchmark reconfiguration throughput
  pod-spinup                benchmark pods spinup
  cleanup                   cleanup any benchmarks resources

Examples:

  $ # create a k3d cluster
  $ runner.sh --cluster-provider=k3d setup

  $ # build, push and deploy the latest version of Ambassador
  $ runner.sh --cluster-provider=k3d deploy ambassador

  $ # run the reconfiguration latency (with 1 replica and 1000 mappings)
  $ runner.sh --cluster-provider=k3d --num-replicas=1 --num-mappings=1000 bench reconf-latency

.
EOF

FORCE=0

load_cluster_local_overrides

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

		# the Ambassador address
	"--hostname" | "--host" | "--address" | "--addr")
		export AMB_EXT_ADDR="$1"
		shift
		;;
	"--hostname="* | "--host="* | "--address="* | "--addr="*)
		export AMB_EXT_ADDR="${opt#*=}"
		;;

		# the Ambassador version to install
	"--amb-version")
		export AMB_VERSION="$1"
		shift
		;;
	"--amb-version="*)
		export AMB_VERSION="${opt#*=}"
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

		# number of mappings
	"--num-mappings" | "--num-map" | "--mappings")
		export MAPPINGS_COUNT="$1"
		shift
		;;
	"--num-mappings="* | "--num-map="* | "--mappings="*)
		export MAPPINGS_COUNT="${opt#*=}"
		;;

		# latency rates
	"--latency-rates" | "--lat-rates" | "--rates")
		export LATENCY_RATES="$1"
		shift
		;;
	"--latency-rates="* | "--late-rates="* | "--rates="*)
		export LATENCY_RATES="${opt#*=}"
		;;

		# latency duration
	"--latency-duration" | "--lat-duration" | "--duration")
		export LATENCY_DURATION="$1"
		shift
		;;
	"--latency-duration="* | "--late-duration="* | "--duration="*)
		export LATENCY_DURATION="${opt#*=}"
		;;

		# latency reports
	"--latency-reports-dir" | "--reports-dir" | "--dir")
		export LATENCY_REPORTS_DIR="$1"
		shift
		;;
	"--latency-reports-dir="* | "--reports-dir="* | "--dir="*)
		export LATENCY_REPORTS_DIR="${opt#*=}"
		;;

		# number of hosts
	"--num-hosts" | "--hosts")
		export HOSTS_COUNT="$1"
		shift
		;;
	"--num-hosts="* | "--hosts="*)
		export HOSTS_COUNT="${opt#*=}"
		;;

		# number of replicas
	"--num-replicas" | "--replicas")
		export REPLICAS_COUNT="$1"
		shift
		;;
	"--num-replicas="* | "--replicas="*)
		export REPLICAS_COUNT="${opt#*=}"
		;;

		# the cluster provider
	"--cluster-provider")
		export CLUSTER_PROVIDER="$1"
		load_cluster_local_overrides
		shift
		;;
	"--cluster-provider="*)
		export CLUSTER_PROVIDER="${opt#*=}"
		load_cluster_local_overrides
		;;

		# cluster arguments
	"--cluster-name")
		export CLUSTER_NAME="$1"
		;;
	"--cluster-name="*)
		export CLUSTER_NAME="${opt#*=}"
		;;
	"--cluster-size")
		export CLUSTER_SIZE="$1"
		;;
	"--cluster-size="*)
		export CLUSTER_SIZE="${opt#*=}"
		;;
	"--cluster-machine" | "--cluster-machines" | "--machines")
		export CLUSTER_MACHINE="$1"
		;;
	"--cluster-machine="* | "--cluster-machines="* | "--machines="*)
		export CLUSTER_MACHINE="${opt#*=}"
		;;
	"--cluster-region")
		export CLUSTER_REGION="$1"
		;;
	"--cluster-region="*)
		export CLUSTER_REGION="${opt#*=}"
		;;
	"--cluster-reuse")
		export CLUSTER_REUSE=1
		;;

		# other things
	"--force")
		export FORCE=1
		;;

	"--keep")
		KEEP=1
		;;

	"--debug")
		set -x
		;;

	"--help")
		echo "$HELP_MSG"
		exit 0
		;;

	*)
		abort "wrong argument $opt"
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

if [[ $# -eq 0 ]]; then
	run
else
	opt=$1
	shift

	case "$opt" in
	"setup" | "create")
		setup
		;;

	"setup-cluster")
		cluster_provider 'create'
		get_env || return 1
		[ -f "$KUBECONFIG" ] || abort "no kubeconfig obtained in KUBECONFIG"
		check_kubeconfig || abort "no valid kubeconfig obtained in KUBECONFIG"
		;;

	"setup-registry" | "create-registry")
		cluster_provider 'create-registry'
		get_env || return 1
		[ -n "$DEV_REGISTRY" ] || abort "no registry obtained in DEV_REGISTRY"
		check_registry || abort "no valid registry at DEV_REGISTRY"
		;;

	"cleanup" | "delete" | "destroy")
		cleanup
		;;

	"reset")
		cleanup || /bin/true
		setup
		;;

	"get-env" | "env")
		eval "$(cluster_provider 'get-env' 2>/dev/null)"
		echo "export KUBECONFIG=$KUBECONFIG"
		echo "export DEV_KUBECONFIG=$DEV_KUBECONFIG"
		echo "export DEV_REGISTRY=$DEV_REGISTRY"
		echo "export DOCKER_NETWORK=$DOCKER_NETWORK"
		echo "export OPERATOR_IMAGE=$(get_full_image_name)"
		echo "export CLUSTER_NAME=$CLUSTER_NAME"
		echo "export CLUSTER_SIZE=$CLUSTER_SIZE"
		echo "export CLUSTER_MACHINE=$CLUSTER_MACHINE"
		echo "export CLUSTER_REGION=$CLUSTER_REGION"
		;;

	"deploy")
		deploy "$1" || abort "Deployment failed."
		;;

	"bench" | "benchmark" | "run")
		bench "$1" || abort "Benchmark failed."
		;;

	"setup-and-bench" | "setup-and-benchmark")
		cleanup || /bin/true
		setup || exit 1
		deploy || exit 1
		bench "all" || abort "Benchmark failed."
		;;

	"all")
		cleanup || /bin/true
		setup || exit 1
		deploy || exit 1
		bench "all" || exit 1
		cleanup
		;;

	"batch")
		machines_list=$(echo $CLUSTER_MACHINE | tr ',' ' ')
		[ -n "$machines_list" ] || {
			warn "no list of machines haave been provided in --cluster-machine. Using a null value."
			machines_list="$DEF_CLUSTER_MACHINE"
		}

		hosts_list=$(echo $HOSTS_COUNT | tr ',' ' ')
		[ -n "$hosts_list" ] || abort "must provide a comma-separated list of --num-hosts"

		mappings_list=$(echo $MAPPINGS_COUNT | tr ',' ' ')
		[ -n "$mappings_list" ] || abort "must provide a comma-separated list of --num-mappings"

		replicas_list=$(echo $REPLICAS_COUNT | tr ',' ' ')
		[ -n "$replicas_list" ] || abort "must provide a comma-separated list of --num-replicas"

		for machine in $machines_list; do
			machine_short="$(get_cluster_machine_short $machine)"
			rand=$(date '+%s')
			cluster_name="perf${machine_short}${rand}"

			export CLUSTER_MACHINE="$machine"
			export CLUSTER_NAME="$cluster_name"

			info "***********************************************************************************"
			info "************** BATCH: creating configuration $CLUSTER_MACHINE ************** "
			info "***********************************************************************************"
			cleanup || /bin/true
			setup || exit 1
			deploy || exit 1

			for num_map in $mappings_list; do
				export MAPPINGS_COUNT="$num_map"

				for num_hosts in $hosts_list; do
					export HOSTS_COUNT="$num_hosts"

					for num_replicas in $replicas_list; do
						export REPLICAS_COUNT="$num_replicas"

						cfg="$CLUSTER_MACHINE / $(get_test_configuration_str)"

						info "***********************************************************************************"
						info "************** BATCH: benchmarking configuration $cfg ************** "
						info "***********************************************************************************"
						bench "$1" || warn "failed to benchmark on $cfg"
					done
				done
			done

			info "***********************************************************************************"
			info "************** BATCH: releasing cluster for configuration $cfg ************** "
			info "***********************************************************************************"
			cleanup || /bin/true
		done
		;;

	*)
		echo "$HELP_MSG"
		echo
		abort "Unknown command $opt"
		;;

	esac
fi
