#!/bin/bash

tests_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$tests_dir" ] || {
	echo "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}
TOP_DIR=$(realpath $tests_dir/../..)
COMMON_FILE=$TOP_DIR/ci/common.sh

source "$COMMON_FILE"

########################################################################################################################

# the tests directory
TESTSUITES_DIR="$tests_dir/tests"

# namespace for runing tests
TEST_NAMESPACE="$AMB_NAMESPACE"
