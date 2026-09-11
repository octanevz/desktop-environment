#!/bin/bash
set -euo pipefail

# =============================================================================
# This script performs the following tasks:
# - Clones the Alacritty source tree
# - Builds Alacritty from source inside an ubuntu:26.04 Docker container
# - Verifies the runtime dependencies installed by setup-00-packages.sh
# - Installs the binary, terminfo, desktop entry, icon, man pages and
#   the Zsh completion on the host
#
# Run this AFTER setup-00-packages.sh and setup-01-devtools.sh:
# - setup-00-packages.sh installs the libraries the binary needs at run time,
#   which this script verifies
# - setup-01-devtools.sh installs Docker, which the build runs in
#
# Update workflow: bump ALACRITTY_VERSION below to the new tag and re-run this
# script. It re-points the clone at that tag, rebuilds and reinstalls.
# Terminals that are already open keep running the old binary until they are
# restarted.
#
# Why build at all: the archive ships 0.16.1 and Alacritty publishes no Linux
# binaries. Why a container: the ~1.5 GB Rust toolchain is only needed to
# compile, so it lives in a Docker volume and never touches the host. Why
# ubuntu:26.04 rather than rust:latest: the binary links against glibc,
# fontconfig and freetype, and a binary built against a newer glibc than the
# host's will not start - building on the image that matches the target makes
# that question moot.
# =============================================================================

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

# The revision to build - bump this to update. Defaults to the latest
# release tag.
# Set to "master" for the development branch - note that master is
# unversioned (it reports 0.18.0-dev), is not a release, and can regress,
# and that it is rebuilt on every run because there is no version to
# compare against.
ALACRITTY_VERSION="${ALACRITTY_VERSION:-v0.17.0}"

# Where the source tree lives on the host (bind-mounted into the container).
ALACRITTY_SRC="${ALACRITTY_SRC:-$HOME/alacritty}"

# Build image - must match the target distribution, see the header.
BUILD_IMAGE="ubuntu:26.04"

# Docker volume holding the cargo/rustup caches, so re-runs do not download
# the toolchain again. Remove it with: docker volume rm alacritty-rust-cache
CACHE_VOLUME="alacritty-rust-cache"

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# -----------------------------------------------------------------------------
# Parse the arguments
# -----------------------------------------------------------------------------
# Rebuild and reinstall even when the installed version already matches, via
# either FORCE=1 ./setup-04-alacritty.sh or ./setup-04-alacritty.sh --force
FORCE="${FORCE:-0}"

for arg in "$@"; do
    case "$arg" in
        -f | --force)
            FORCE=1
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Usage: $0 [--force]" >&2
            exit 1
            ;;
    esac
done

setup_begin "$@"

# -----------------------------------------------------------------------------
# Check the prerequisites
# -----------------------------------------------------------------------------
step "Check the prerequisites"
if ! command -v docker > /dev/null 2>&1; then
    echo "Docker is not installed. Run setup-01-devtools.sh first." >&2
    exit 1
fi

if ! docker info > /dev/null 2>&1; then
    echo "Cannot talk to the Docker daemon. Make sure it is running and that" >&2
    echo "you have logged out and back in since setup-01-devtools.sh added you" >&2
    echo "to the docker group." >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# Verify the runtime dependencies
# -----------------------------------------------------------------------------
# The libraries the finished binary needs at run time are installed by
# setup-00-packages.sh, not here - this script only checks for them. Installing
# them here as well would blur the line this split exists to draw: the host
# gets runtime libraries, the container gets everything needed to compile.
#
# Their BUILD counterparts - build-essential, cmake, pkg-config, python3,
# libfreetype6-dev, libfontconfig1-dev, libxcb-xfixes0-dev, libxkbcommon-dev
# and the Rust toolchain - are installed INSIDE the ubuntu:26.04 container
# further down and must never be hoisted onto the host. Keeping the ~1.5 GB
# toolchain and the -dev packages off the host is the whole point of building
# in a container; adding them to setup-00-packages.sh would defeat it.
step "Verify the runtime dependencies"
ALACRITTY_RUNTIME_LIBS=(
    libfontconfig1
    libfreetype6
    libwayland-client0
    libxcb-xfixes0
    libxkbcommon0
    libxkbcommon-x11-0
)

log "Verifying the Alacritty runtime libraries..."
MISSING_LIBS=()
for pkg in "${ALACRITTY_RUNTIME_LIBS[@]}"; do
    if ! dpkg-query -W -f='${Status}' "$pkg" 2> /dev/null | grep -q "^install ok installed$"; then
        MISSING_LIBS+=("$pkg")
    fi
done

if [ "${#MISSING_LIBS[@]}" -gt 0 ]; then
    echo "Missing Alacritty runtime libraries: ${MISSING_LIBS[*]}" >&2
    echo "They are installed by setup-00-packages.sh - run that first, then" >&2
    echo "re-run this script." >&2
    exit 1
fi

# desktop-file-install (desktop-file-utils) installs the desktop entry. It is
# an install-time helper rather than a runtime library, but it comes from
# setup-00-packages.sh all the same, because this script performs no apt
# installs on the host at all. tic, the other helper, is in ncurses-bin, which
# is Essential and cannot be missing.
if ! command -v desktop-file-install > /dev/null 2>&1; then
    echo "desktop-file-install is missing. It comes from desktop-file-utils," >&2
    echo "installed by setup-00-packages.sh - run that first, then re-run this" >&2
    echo "script." >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# Check out the requested revision
# -----------------------------------------------------------------------------
# Both paths below - fresh clone and existing clone - have to end up at
# exactly $ALACRITTY_VERSION. An existing clone is left at whatever was built
# last time, so it is never enough to just reuse it: the requested revision is
# always fetched and checked out, which is what makes bumping the variable and
# re-running work.
#
# Note that the checkout is forced, so any local edits in $ALACRITTY_SRC are
# discarded. This is a build tree, not a place to work in.
step "Check out the requested revision"
ALACRITTY_REPO="https://github.com/alacritty/alacritty.git"

if [ ! -d "$ALACRITTY_SRC/.git" ]; then
    log "Cloning Alacritty $ALACRITTY_VERSION into $ALACRITTY_SRC..."
    git clone --depth 1 --branch "$ALACRITTY_VERSION" "$ALACRITTY_REPO" "$ALACRITTY_SRC"
elif [ "$ALACRITTY_VERSION" = "master" ]; then
    log "Fetching master into the existing checkout at $ALACRITTY_SRC..."
    git -C "$ALACRITTY_SRC" fetch --depth 1 origin master
    git -C "$ALACRITTY_SRC" checkout --force FETCH_HEAD
else
    # git fetch exits non-zero when the tag does not exist upstream, and
    # set -e turns that into a loud failure rather than a stale rebuild.
    log "Fetching tag $ALACRITTY_VERSION into the existing checkout at $ALACRITTY_SRC..."
    if ! git -C "$ALACRITTY_SRC" fetch --depth 1 origin tag "$ALACRITTY_VERSION"; then
        echo "Tag $ALACRITTY_VERSION does not exist in $ALACRITTY_REPO." >&2
        echo "Check ALACRITTY_VERSION against the upstream releases." >&2
        exit 1
    fi
    git -C "$ALACRITTY_SRC" checkout --force "refs/tags/$ALACRITTY_VERSION"
fi

# Reported as the requested revision plus the commit, because the repo also
# carries per-crate tags (alacritty_terminal_*) that "git describe" would
# pick up instead.
log "Source tree is at $ALACRITTY_VERSION ($(git -C "$ALACRITTY_SRC" rev-parse --short HEAD))."

# -----------------------------------------------------------------------------
# Stop here when the installed version already matches
# -----------------------------------------------------------------------------
# The build is gated on a version mismatch, not on alacritty merely being
# installed - otherwise bumping ALACRITTY_VERSION would be a no-op. When the
# versions match the script ends here: the install steps below read the build
# output from $ALACRITTY_SRC/target, which a fresh clone does not have.
#
# "alacritty --version" prints "alacritty 0.17.0", while ALACRITTY_VERSION is
# a tag like "v0.17.0", so the leading "v" is stripped before comparing.
# master has no version to compare against and is always rebuilt.
WANTED_VERSION="${ALACRITTY_VERSION#v}"
INSTALLED_VERSION=""
if [ -x /usr/local/bin/alacritty ]; then
    INSTALLED_VERSION="$(/usr/local/bin/alacritty --version | awk '{ print $2 }')"
fi

if [ "$FORCE" = "1" ]; then
    log "FORCE is set - rebuilding $ALACRITTY_VERSION."
elif [ "$ALACRITTY_VERSION" = "master" ]; then
    log "Building master - it is unversioned, so it is always rebuilt."
elif [ -z "$INSTALLED_VERSION" ]; then
    log "Alacritty is not installed in /usr/local/bin yet."
elif [ "$INSTALLED_VERSION" = "$WANTED_VERSION" ]; then
    log "Alacritty $WANTED_VERSION is already installed. Nothing to do."
    log "Rebuild and reinstall it anyway with: FORCE=1 $0"
    exit 0
else
    log "Installed Alacritty is $INSTALLED_VERSION, want $WANTED_VERSION - rebuilding."
fi

# -----------------------------------------------------------------------------
# Build inside an ubuntu:26.04 container
# -----------------------------------------------------------------------------
# Below the version check above, which exits 0 when the wanted version is
# already installed - that path changes nothing and must lose nothing.
step "Build inside an ubuntu:26.04 container"
setup_invalidate

log "Building Alacritty $ALACRITTY_VERSION in a $BUILD_IMAGE container..."

docker volume create "$CACHE_VOLUME" > /dev/null

# The container runs as root because it has to apt install its build
# dependencies, so everything it writes into the bind mount lands as root.
# HOST_UID/HOST_GID are passed in so the container hands the artifacts back
# to the invoking user before it exits.
docker run --rm -i \
    -e HOST_UID="$(id -u)" \
    -e HOST_GID="$(id -g)" \
    -e DEBIAN_FRONTEND=noninteractive \
    -e CARGO_HOME=/opt/rust/cargo \
    -e RUSTUP_HOME=/opt/rust/rustup \
    -v "$ALACRITTY_SRC:/build" \
    -v "$CACHE_VOLUME:/opt/rust" \
    -w /build \
    "$BUILD_IMAGE" bash -euo pipefail -s << 'CONTAINER_SCRIPT'

# Build dependencies. scdoc is included because the man pages are generated
# from extra/man/*.scd, which keeps scdoc off the host as well.
apt update -y
apt install -y \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    gzip \
    libfontconfig1-dev \
    libfreetype6-dev \
    libxcb-xfixes0-dev \
    libxkbcommon-dev \
    pkg-config \
    python3 \
    scdoc

# Install the Rust toolchain (minimal profile - no docs, no clippy).
# CARGO_HOME/RUSTUP_HOME point at the Docker volume, so this is downloaded
# once and reused by later runs.
if [ ! -x /opt/rust/cargo/bin/cargo ]; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --no-modify-path --profile minimal --default-toolchain stable
else
    /opt/rust/cargo/bin/rustup update stable
fi
export PATH="/opt/rust/cargo/bin:$PATH"

cargo build --release

# Generate the man pages next to the binary so the host side can install them.
mkdir -p target/man
scdoc < extra/man/alacritty.1.scd          | gzip -c > target/man/alacritty.1.gz
scdoc < extra/man/alacritty-msg.1.scd      | gzip -c > target/man/alacritty-msg.1.gz
scdoc < extra/man/alacritty.5.scd          | gzip -c > target/man/alacritty.5.gz
scdoc < extra/man/alacritty-bindings.5.scd | gzip -c > target/man/alacritty-bindings.5.gz
scdoc < extra/man/alacritty-escapes.7.scd  | gzip -c > target/man/alacritty-escapes.7.gz

# Hand the build output back to the invoking user.
chown -R "$HOST_UID:$HOST_GID" target

CONTAINER_SCRIPT

log "Build completed successfully!"

# -----------------------------------------------------------------------------
# Install the binary
# -----------------------------------------------------------------------------
step "Install the binary"
log "Installing Alacritty into /usr/local..."
sudo install -m 755 "$ALACRITTY_SRC/target/release/alacritty" /usr/local/bin/alacritty

# -----------------------------------------------------------------------------
# Install the terminfo
# -----------------------------------------------------------------------------
step "Install the terminfo"
log "Installing the terminfo..."
sudo tic -xe alacritty,alacritty-direct "$ALACRITTY_SRC/extra/alacritty.info"

# -----------------------------------------------------------------------------
# Install the desktop entry and icon
# -----------------------------------------------------------------------------
step "Install the desktop entry and icon"
log "Installing the desktop entry and icon..."
# /usr/share/pixmaps is the path the shipped .desktop file expects; the entry
# itself goes to /usr/local/share/applications, where locally built software
# belongs (it is on the default XDG_DATA_DIRS).
sudo install -D -m 644 "$ALACRITTY_SRC/extra/logo/alacritty-term.svg" /usr/share/pixmaps/Alacritty.svg
sudo desktop-file-install --dir=/usr/local/share/applications "$ALACRITTY_SRC/extra/linux/Alacritty.desktop"
sudo update-desktop-database /usr/local/share/applications

# -----------------------------------------------------------------------------
# Install the man pages
# -----------------------------------------------------------------------------
step "Install the man pages"
log "Installing the man pages..."
sudo install -D -m 644 "$ALACRITTY_SRC/target/man/alacritty.1.gz" /usr/local/share/man/man1/alacritty.1.gz
sudo install -D -m 644 "$ALACRITTY_SRC/target/man/alacritty-msg.1.gz" /usr/local/share/man/man1/alacritty-msg.1.gz
sudo install -D -m 644 "$ALACRITTY_SRC/target/man/alacritty.5.gz" /usr/local/share/man/man5/alacritty.5.gz
sudo install -D -m 644 "$ALACRITTY_SRC/target/man/alacritty-bindings.5.gz" /usr/local/share/man/man5/alacritty-bindings.5.gz
sudo install -D -m 644 "$ALACRITTY_SRC/target/man/alacritty-escapes.7.gz" /usr/local/share/man/man7/alacritty-escapes.7.gz

# -----------------------------------------------------------------------------
# Install the Zsh completion
# -----------------------------------------------------------------------------
# setup-00-packages.sh makes Zsh the default shell, so only the Zsh completion
# is installed here. It goes into Oh My Zsh's custom/completions directory,
# which is on fpath before compinit runs (see the herdr completion in
# setup-01-devtools.sh for why that matters).
step "Install the Zsh completion"
log "Installing the Zsh completion..."
ZSH_COMPLETIONS="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/completions"
mkdir -p "$ZSH_COMPLETIONS"
install -m 644 "$ALACRITTY_SRC/extra/completions/_alacritty" "$ZSH_COMPLETIONS/_alacritty"

# -----------------------------------------------------------------------------
# Verify the installation
# -----------------------------------------------------------------------------
step "Verify the installation"
log "Alacritty installation completed successfully!"
/usr/local/bin/alacritty --version
log "Terminals that are already open keep the old binary until restarted."

setup_end
