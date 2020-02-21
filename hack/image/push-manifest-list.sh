#!/usr/bin/env bash

this_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$this_dir" ] || {
	echo "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}
TOP_DIR=$(realpath $this_dir/../..)
COMMON_FILE=$TOP_DIR/ci/common.sh

source "$COMMON_FILE"

#
# push_manifest_list <source_image> <push_image> [<arch1> <arch2> <archN>]
#
# push_manifest_list uses the pre-pushed images for each
# supported architecture and pushes a manifest list for each
# of the tags from the Travis CI envionment (created during
# the image push job).
#
function push_manifest_list() {
	push_image=$1
	shift || fatal "${FUNCNAME} usage error"
	arches=$@

	docker_login $push_image

	check_can_push || return 0

	tags=$(get_image_tags)
	for tag in $tags; do
		info "Pushing image $push_image:$tag..."
		images_with_arches=$(get_arch_images $push_image $tag $arches)
		DOCKER_CLI_EXPERIMENTAL="enabled" docker manifest create $push_image:$tag $images_with_arches
		DOCKER_CLI_EXPERIMENTAL="enabled" docker manifest push --purge $push_image:$tag
	done
}

function get_arch_images() {
	image=$1
	shift || fatal "${FUNCNAME} usage error"
	tag=$1
	shift || fatal "${FUNCNAME} usage error"
	arches="$@"
	for arch in $arches; do
		echo "$image-$arch:$tag"
	done
}

push_manifest_list "$@"
