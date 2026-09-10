#!/bin/bash
set -euo pipefail

# =============================================================================
# This script performs the following tasks:
# - Detects the running GNOME Shell version
# - Downloads Caffeine and Tiling Shell from extensions.gnome.org for exactly
#   that shell version
# - Installs them per-user and enables them
# - Loads their settings from config/dconf with dconf load
#
# Run this AFTER setup-00-packages.sh, which installs curl, python3, dconf-cli
# and gnome-shell-extension-manager (for managing and configuring the
# extensions from a GUI afterwards); this script verifies they are there.
# gnome-shell and its gnome-extensions tool are required and expected to be
# present already; the script stops if they are not.
#
# Extension builds are per shell version, so the shell version is detected at
# runtime rather than hardcoded, and the script refuses to install anything
# that is not published for it.
#
# The settings for both extensions ARE carried over: they are deployed from
# config/dconf/*.ini with "dconf load". To capture your own, configure the
# extensions through Extension Manager and re-dump them into the repo:
#
#   dconf dump /org/gnome/shell/extensions/caffeine/ \
#       > config/dconf/caffeine.ini
#   dconf dump /org/gnome/shell/extensions/tilingshell/ \
#       > config/dconf/tiling-shell.ini
#
# Whatever is currently in dconf is dumped to a backup before anything is
# written, so a load never loses settings that were never dumped.
# =============================================================================

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
EGO_URL="https://extensions.gnome.org"

EXTENSION_UUIDS=(
    caffeine@patapon.info
    tilingshell@ferrarodomenico.com
)

EXTENSIONS_DIR="$HOME/.local/share/gnome-shell/extensions"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DCONF_DIR="$SCRIPT_DIR/config/dconf"

# Each entry pairs the dconf path an extension keeps its settings under with
# the dump loaded into it. The paths are the extensions' own and are not
# derived from the UUIDs - tilingshell@ferrarodomenico.com stores its settings
# under /org/gnome/shell/extensions/tilingshell/.
DCONF_SETTINGS=(
    "/org/gnome/shell/extensions/caffeine/|caffeine.ini"
    "/org/gnome/shell/extensions/tilingshell/|tiling-shell.ini"
)

DCONF_BACKUP_DIR="$HOME/.local/state/gnome-extension-settings"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# -----------------------------------------------------------------------------
# Parse the arguments
# -----------------------------------------------------------------------------
# Already-installed extensions are skipped. --force (or FORCE=1) re-downloads
# and reinstalls them, which also picks up a newer release.
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
# Verify the prerequisites
# -----------------------------------------------------------------------------
MISSING_COMMANDS=()
for cmd in curl dconf python3; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
        MISSING_COMMANDS+=("$cmd")
    fi
done

if [ "${#MISSING_COMMANDS[@]}" -gt 0 ]; then
    echo "Missing prerequisites: ${MISSING_COMMANDS[*]}" >&2
    echo "They are installed by setup-00-packages.sh - run that first, then" >&2
    echo "re-run this script." >&2
    exit 1
fi

if ! command -v gnome-shell > /dev/null 2>&1; then
    echo "gnome-shell was not found. This script only makes sense on a GNOME" >&2
    echo "desktop." >&2
    exit 1
fi

# gnome-extensions ships with gnome-shell and does the installing and enabling
# here, so it is a hard requirement rather than something to work around.
if ! command -v gnome-extensions > /dev/null 2>&1; then
    echo "gnome-extensions was not found. It ships with gnome-shell, so this" >&2
    echo "is an incomplete GNOME installation - fix that and re-run." >&2
    exit 1
fi

# Extension Manager comes from setup-00-packages.sh; it is not needed to install
# the extensions, only to configure them afterwards, so this is a warning.
if ! command -v gnome-extensions-app > /dev/null 2>&1 &&
    ! command -v extension-manager > /dev/null 2>&1; then
    log "Warning: Extension Manager was not found."
    log "setup-00-packages.sh installs gnome-shell-extension-manager for it."
fi

# -----------------------------------------------------------------------------
# Detect the GNOME Shell version
# -----------------------------------------------------------------------------
# "gnome-shell --version" prints e.g. "GNOME Shell 50.1"; extensions are
# published against the major version ("50"), which is what the API expects.
SHELL_VERSION="$(gnome-shell --version | awk '{ print $3 }')"
SHELL_MAJOR="${SHELL_VERSION%%.*}"

log "Detected GNOME Shell $SHELL_VERSION (extensions for shell $SHELL_MAJOR)."

# -----------------------------------------------------------------------------
# Install the extensions
# -----------------------------------------------------------------------------
# The extension-info API is queried per extension. Its shell_version_map is
# the authoritative answer - it maps each supported shell version to the
# release built for it, and that entry's "pk" is the version_tag the download
# URL needs. The top-level download_url is not used: for an unsupported shell
# version it falls back to some other build instead of failing.
DOWNLOAD_DIR="$(mktemp -d)"
trap 'rm -rf "$DOWNLOAD_DIR"' EXIT

for uuid in "${EXTENSION_UUIDS[@]}"; do
    if [ -d "$EXTENSIONS_DIR/$uuid" ] && [ "$FORCE" != "1" ]; then
        log "$uuid is already installed. Skipping (use --force to reinstall)."
        continue
    fi

    log "Querying extensions.gnome.org for $uuid..."
    INFO="$(curl -fsSL "$EGO_URL/extension-info/?uuid=$uuid")"

    # Prints "<pk> <version>" for the matching shell, or nothing at all.
    RELEASE="$(printf '%s' "$INFO" | python3 -c "
import json, sys
info = json.load(sys.stdin)
release = (info.get('shell_version_map') or {}).get('$SHELL_MAJOR')
if release:
    print(release['pk'], release['version'])
")"

    if [ -z "$RELEASE" ]; then
        echo "$uuid has no release for GNOME Shell $SHELL_MAJOR." >&2
        echo "Refusing to install a build for a different shell version." >&2
        echo "Check $EGO_URL/extension/ for its supported versions." >&2
        exit 1
    fi

    VERSION_TAG="${RELEASE% *}"
    EXTENSION_VERSION="${RELEASE#* }"

    log "Downloading $uuid version $EXTENSION_VERSION..."
    ZIP="$DOWNLOAD_DIR/$uuid.shell-extension.zip"
    curl -fsSL -o "$ZIP" \
        "$EGO_URL/download-extension/$uuid.shell-extension.zip?version_tag=$VERSION_TAG"

    gnome-extensions install --force "$ZIP"

    log "Installed $uuid version $EXTENSION_VERSION."
done

# -----------------------------------------------------------------------------
# Enable the extensions
# -----------------------------------------------------------------------------
# "gnome-extensions enable" writes to the current user's session settings, so
# it needs a session to talk to. Without one the extensions stay installed but
# disabled, and can be enabled after logging in.
if [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]; then
    for uuid in "${EXTENSION_UUIDS[@]}"; do
        if gnome-extensions enable "$uuid" 2> /dev/null; then
            log "Enabled $uuid."
        else
            log "Could not enable $uuid - enable it after logging back in."
        fi
    done
else
    log "No GNOME session detected - the extensions were installed but not"
    log "enabled. After logging in, run:"
    for uuid in "${EXTENSION_UUIDS[@]}"; do
        log "  gnome-extensions enable $uuid"
    done
fi

# -----------------------------------------------------------------------------
# Load the extension settings
# -----------------------------------------------------------------------------
# "dconf load" writes a whole subtree at once: it sets every key the dump names
# and leaves anything else under that path alone. A load overwrites changes
# made through Extension Manager since the dump was taken, so the current
# settings are saved first whenever they differ from the dump - which, for
# Tiling Shell, is usually: it rewrites some of the dumped keys itself
# (selected-layouts, last-version-name-installed), so expect a backup and a
# reload on most re-runs, not a no-op.
#
# This works with or without a running shell - dconf is only a database, and
# the extensions read it when the shell next starts them.
#
# last-version-name-installed in tiling-shell.ini is written by the extension
# and suppresses its "what's new" screen; it is carried over as dumped.
for entry in "${DCONF_SETTINGS[@]}"; do
    DCONF_PATH="${entry%%|*}"
    DUMP_NAME="${entry##*|}"
    DUMP_FILE="$DCONF_DIR/$DUMP_NAME"

    if [ ! -f "$DUMP_FILE" ]; then
        echo "Missing $DUMP_FILE - is the repo complete?" >&2
        exit 1
    fi

    CURRENT="$(dconf dump "$DCONF_PATH")"

    if [ "$CURRENT" = "$(cat "$DUMP_FILE")" ]; then
        log "$DCONF_PATH is already up to date."
        continue
    fi

    # Nothing to back up on a fresh machine, where the subtree is still empty.
    if [ -n "$CURRENT" ]; then
        mkdir -p "$DCONF_BACKUP_DIR"
        BACKUP="$DCONF_BACKUP_DIR/$DUMP_NAME.bak-$TIMESTAMP"
        printf '%s\n' "$CURRENT" > "$BACKUP"
        log "Backed up $DCONF_PATH -> $BACKUP"
    fi

    if dconf load "$DCONF_PATH" < "$DUMP_FILE"; then
        log "Loaded $DUMP_NAME into $DCONF_PATH."
    else
        log "Could not write $DCONF_PATH. Load it by hand with:"
        log "  dconf load $DCONF_PATH < $DUMP_FILE"
    fi
done

# -----------------------------------------------------------------------------
# Verify the installation
# -----------------------------------------------------------------------------
for uuid in "${EXTENSION_UUIDS[@]}"; do
    METADATA="$EXTENSIONS_DIR/$uuid/metadata.json"
    if [ -f "$METADATA" ]; then
        INSTALLED="$(python3 -c "
import json
print(json.load(open('$METADATA')).get('version', 'unknown'))
")"
        log "$uuid: version $INSTALLED"
    else
        log "$uuid: not installed"
    fi
done

log "GNOME extensions installation completed successfully!"

# -----------------------------------------------------------------------------
# Log out to load the extensions
# -----------------------------------------------------------------------------
# Enabling an extension does not load it into the running shell. On X11 the
# shell can be restarted with Alt+F2 r, but Ubuntu 26.04 defaults to Wayland,
# where that does not exist - the session has to be ended and started again.
log ""
log "Log out and log back in for the extensions to load."
log "On Wayland a full log out is required - restarting the shell is not"
log "enough. The settings loaded above are picked up at the same time."
log ""
log "After changing anything in Extension Manager, re-dump it into the repo"
log "so the next machine gets it - see the comment at the top of this script."

setup_end
