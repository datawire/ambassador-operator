#!/bin/bash

this_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$this_dir" ] || {
	echo "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}
TOP_DIR=$(realpath $this_dir/..)
COMMON_FILE=$TOP_DIR/ci/common.sh

source "$COMMON_FILE"

set -o errexit
set -o nounset
set -o pipefail

echo "Checking for license header..."
allfiles=$(list_files)
licRes=""
for file in $allfiles; do
	if ! head -n3 "${file}" | grep -Eq "(Copyright|generated|GENERATED)"; then
		licRes="${licRes}\n"$(echo -e "  ${file}")
	fi
done
if [ -n "${licRes}" ]; then
	echo -e "license header checking failed:\n${licRes}"
	exit 255
fi
