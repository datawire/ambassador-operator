#!/usr/bin/env bash

this_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$this_dir" ] || {
	info "FATAL: no current dir (maybe running in zsh?)"
	exit 1
}
TOP_DIR=$(realpath $this_dir/../..)
COMMON_FILE=$TOP_DIR/ci/common.sh

# shellcheck source=../../ci/common.sh
source "$COMMON_FILE"

#
# push_image_tags <source_image> <push_image>
#
# push_image_tags tags the source docker image with zero or more
# image tags based on TravisCI environment variables and the
# presence of git tags in the repository of the current working
# directory. If a second argument is present, it will be used as
# the base image name in pushed image tags.
#
function push_image_tags() {

	local source_image=$1
	shift || fatal "${FUNCNAME} usage error"
	local push_image=$1
	shift || push_image="$source_image"

	print_image_info "$source_image"
	print_git_tags
	docker_login "$push_image"

	local latest_image=""

	info "Tagging $source_image -> $push_image..."
	docker tag "$source_image" "$push_image"
	if is_latest_tag "$(get_image_tag $push_image)"; then
		latest_image="$(get_image_server_and_path $push_image)/$(get_image_name $push_image):latest"
		info "Tagging $source_image -> $latest_image..."
		docker tag "$source_image" "$latest_image"
	fi

	if check_can_push; then
		info "Pushing $source_image -> $push_image..."
		docker push "$push_image"
		if is_latest_tag "$(get_image_tag $push_image)"; then
			info "Pushing $source_image -> $latest_image"
			docker push "$push_image"
		fi
	else
		info "(push skipped)"
	fi
}

#
# print_image_info <image_name>
#
# print_image_info prints helpful information about a docker
# image.
#
function print_image_info() {
	image_name=$1
	shift || fatal "${FUNCNAME} usage error"
	image_id=$(docker inspect "$image_name" -f "{{.Id}}")
	image_created=$(docker inspect "$image_name" -f "{{.Created}}")

	if [[ -n "$image_id" ]]; then
		info "Docker image info:"
		info "    Name:      $image_name"
		info "    ID:        $image_id"
		info "    Created:   $image_created"
		info ""
	else
		abort "Could not find docker image \"$image_name\""
	fi
}

#
# latest_git_version
#
# latest_git_version returns the highest semantic version
# number found in the repository, with the form "vX.Y.Z".
# Version numbers not matching the semver release format
# are ignored.
#
function latest_git_version() {
	git tag -l | egrep "${semver_regex}" | sort -V | tail -1
}

push_image_tags "$@"
