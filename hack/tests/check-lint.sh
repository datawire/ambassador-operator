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

PATH=$PATH:$(go env GOPATH)/bin

DEV_LINTERS=(
	##todo(camilamacedo86): The following checks requires fixes in the code.
	##todo(camilamacedo86): they should be enabled and added in the CI
	"--enable=gocyclo"
	"--enable=lll"
	"--enable=gosec" # NOT add this one to CI since was defined that it should be optional for now at least.
)

# Some lint checks can be fixed automatically by using it.
FIX_LINTERS=(
	"--fix"
)

subcommand=$1
case $subcommand in
"fix")
	info "Running lint check with automatically fix"
	LINTERS=${FIX_LINTERS[@]}
	;;
"dev")
	##todo(camilamacedo86): It should be removed when all linter checks be enabled
	info "Checking the project with all linters (dev)"
	LINTERS=${DEV_LINTERS[@]}
	;;
"ci")
	info "Checking the project with the linters enabled for the ci"
	;;
*)
	echo "Must pass 'dev' or 'ci' argument"
	exit 1
	;;
esac

info "Running golangci-lint"
golangci-lint run --disable-all \
	--deadline 5m \
	--enable=deadcode \
	--enable=dupl \
	--enable=dupl \
	--enable=errcheck \
	--enable=goconst \
	--enable=gofmt \
	--enable=golint \
	--enable=ineffassign \
	--enable=interfacer \
	--enable=maligned \
	--enable=misspell \
	--enable=nakedret \
	--enable=prealloc \
	--enable=structcheck \
	--enable=stylecheck \
	--enable=unconvert \
	--enable=unparam \
	--enable=varcheck \
	${LINTERS[@]}
