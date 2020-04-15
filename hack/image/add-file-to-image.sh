#!/bin/bash

this_script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
[ -d "$this_script_dir" ] || {
    echo "FATAL: no current dir (maybe running in zsh?)"
    exit 1
}

TOP_DIR=$(realpath $this_script_dir/../..)
COMMON_FILE=$TOP_DIR/ci/common.sh

. "$COMMON_FILE"

############################################################################################

IMAGE="ambassador-operator:dev"
FILE_PATH=""
CONTENT=""
NEW_IMAGE=""
CHECK=""

############################################################################################

while [[ $# -gt 0 ]] && [[ "$1" == "--"* ]]; do
    opt="$1"
    shift #expose next argument
    case "$opt" in
    "--")
        break 2
        ;;

        # the image name
    "--image")
        export IMAGE_NAME="$1"
        shift
        ;;
    "--image="*)
        export IMAGE_NAME="${opt#*=}"
        ;;

        # the file path
    "--path" | "--file")
        export FILE_PATH="$1"
        shift
        ;;
    "--path="* | "--file="*)
        export FILE_PATH="${opt#*=}"
        ;;

        # the file content
    "--content")
        export CONTENT="$1"
        shift
        ;;
    "--content="*)
        export CONTENT="${opt#*=}"
        ;;

        # the new image name
    "--new-image")
        export NEW_IMAGE_NAME="$1"
        shift
        ;;
    "--new-image="*)
        export NEW_IMAGE_NAME="${opt#*=}"
        ;;

    "--debug")
        set -x
        ;;

    "--check")
        CHECK=1
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

[ -n "$FILE_PATH" ] || abort "no --path provided"
[ -n "$CONTENT" ] || abort "no --content provided"

DIR_NAME=$(dirname $FILE_PATH)
TEMP_NAME="add-file-snapshot"

docker stop "$TEMP_NAME" >/dev/null 2>&1
docker rm "$TEMP_NAME" >/dev/null 2>&1

info "Adding file $FILE_PATH to $IMAGE (in container $TEMP_NAME)"
docker run --name "$TEMP_NAME" \
    --entrypoint /bin/sh \
    "$IMAGE" \
    -c "mkdir -p ${DIR_NAME} ; echo '${CONTENT}' > $FILE_PATH"

info "Comitting file to $TEMP_NAME"
docker commit -m="Added file $FILE_PATH" "$TEMP_NAME" "$TEMP_NAME"

if [ -n "$NEW_IMAGE" ] && [ "$IMAGE" != "$NEW_IMAGE" ] ; then
    info "Saving as new image $NEW_IMAGE"
else
    info "Replacing old $IMAGE: removing"
    docker rmi --force "$IMAGE"
fi

info "... tagging $TEMP_NAME -> $IMAGE"
docker tag "$TEMP_NAME" $IMAGE

info "Removing temporary $TEMP_NAME"
docker rmi --force "$TEMP_NAME"
docker stop "$TEMP_NAME" >/dev/null 2>&1
docker rm "$TEMP_NAME" >/dev/null 2>&1

if [ -n "$CHECK" ] ; then
    info "Checking file exists. Contents:"
    hl
    docker run -ti --entrypoint /bin/sh --rm $IMAGE  -c "cat $FILE_PATH"
    hl
fi
