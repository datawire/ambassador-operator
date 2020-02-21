#!/usr/bin/env bash

cleanup_sh_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$cleanup_sh_dir" ] || {
	echo "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}

# shellcheck source=common.sh
source "$cleanup_sh_dir/common.sh"

info "Nothing to cleanup"
