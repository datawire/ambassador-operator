#!/bin/bash

cov_sh_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$cov_sh_dir" ] || {
	echo "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}
TOP_DIR=$(realpath $cov_sh_dir/..)

# shellcheck source=common.sh
source "$cov_sh_dir/common.sh"

#################################################################################################

EXE_CODECOV="/tmp/codecov.sh"

# config file (relative to the top directory)
CODECOD_YAML=".codecov.yml"

#################################################################################################

info "Downloading code codecov script"
rm -f "$EXE_CODECOV"
curl -L -o "$EXE_CODECOV" -s https://codecov.io/bash

chmod 755 "$EXE_CODECOV"

info "Running codecov with config from $CODECOD_YAML"
cd "$TOP_DIR" && $EXE_CODECOV -y "$CODECOD_YAML"

