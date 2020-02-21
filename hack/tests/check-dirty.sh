#!/usr/bin/env bash

set -e

this_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$this_dir" ] || {
	echo "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}
TOP_DIR=$(realpath $this_dir/../..)
COMMON_FILE=$TOP_DIR/ci/common.sh

# shellcheck source=../../ci/common.sh
source "$COMMON_FILE"

export GIT_PAGER=

modified=$(git diff --name-only | grep -v go.mod | grep -v go.sum | wc -l)
if [ "$modified" != "0" ]; then
	info "Some files seem to be dirty now. Differences:"
	info "----------------------------------------------------------------------------"
	(cd $TOP_DIR && git diff)
	info "----------------------------------------------------------------------------"
	abort "make sure you 'make generate' or 'make format' before submitting your PR"
fi

exit 0
