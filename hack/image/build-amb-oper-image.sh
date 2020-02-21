#!/usr/bin/env bash

this_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$this_dir" ] || {
	echo "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}
TOP_DIR=$(realpath $this_dir/../..)
COMMON_FILE=$TOP_DIR/ci/common.sh

source "$COMMON_FILE"

set -eu

info "(running 'operator-sdk build')"
operator-sdk build $1
