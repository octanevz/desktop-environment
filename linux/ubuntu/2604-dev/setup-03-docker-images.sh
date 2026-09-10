#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
# All of these are floating tags, so pulling again months later fetches a
# different image. Note that the -trixie suffix is the image's own base
# distribution, not the host's.
#
# ubuntu:26.04 is the image setup-04-alacritty.sh compiles in. That script would
# pull it on its own the first time it runs, so having it here only moves the
# download to a predictable moment - and re-running this script refreshes it,
# which "docker run" never does once the tag is present locally.
DOCKER_IMAGES=(
    postgres:18-trixie
    quay.io/jupyter/scipy-notebook:latest
    quay.io/jupyter/pytorch-notebook:latest
    ubuntu:26.04
)

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
setup_begin "$@"

# -----------------------------------------------------------------------------
# Install the required Docker images
# -----------------------------------------------------------------------------
# Pulling a moved tag does not remove what it replaces: the tag is repointed at
# the new image and the old one is left behind untagged, keeping whichever
# layers the new image does not share. Only the previous version of each image
# pulled here is removed, by remembering its ID across the pull - a blanket
# "docker image prune" would also delete unrelated untagged images that have
# nothing to do with this script.
for image in "${DOCKER_IMAGES[@]}"; do
    OLD_ID="$(docker image inspect --format '{{.Id}}' "$image" 2> /dev/null || true)"

    docker pull "$image"

    NEW_ID="$(docker image inspect --format '{{.Id}}' "$image")"

    if [ -z "$OLD_ID" ] || [ "$OLD_ID" = "$NEW_ID" ]; then
        continue
    fi

    # Docker may have dropped the old image already, in which case there is
    # nothing left to clean up.
    if ! docker image inspect "$OLD_ID" > /dev/null 2>&1; then
        continue
    fi

    # The pull replaced the image. Remove the previous one, but only if the
    # pull left it untagged - if it still carries a tag, something else refers
    # to it and it is not ours to delete. Docker deletes an image by ID as long
    # as it has at most one tag, so this check is what protects that tag. The
    # inspect is its own statement so that a failure stops the script (set -e)
    # instead of reading as "no tags left".
    OLD_TAGS="$(docker image inspect --format '{{len .RepoTags}}' "$OLD_ID")"
    if [ "$OLD_TAGS" != "0" ]; then
        log "Previous $image is still tagged elsewhere - keeping it."
        continue
    fi

    log "Removing the previous $image (${OLD_ID:7:12})..."
    if ! docker image rm "$OLD_ID" > /dev/null 2>&1; then
        log "Could not remove it - a container is probably still using it."
    fi
done

log "Docker images are up to date."

setup_end
