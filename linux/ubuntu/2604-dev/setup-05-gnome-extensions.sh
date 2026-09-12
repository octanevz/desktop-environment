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
#
# The script records itself as complete only when nothing was left undone:
# a step that could not reach dconf - over SSH, say - prints the command to
# run inside the desktop and leaves the marker unwritten, so the next plain
# run retries it without --force. This is the same rule setup-07-git.sh
# applies to an unauthenticated gh.
# =============================================================================

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
EGO_URL="https://extensions.gnome.org"

EXTENSION_UUIDS=(
    caffeine@patapon.info
    tilingshell@ferrarodomenico.com
)

# Where "gnome-extensions install" puts them: the XDG user data directory,
# resolved with its default the way setup-06-configs.sh resolves the
# application directories.
EXTENSIONS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions"

# Each entry pairs the dconf path an extension keeps its settings under with
# the dump loaded into it. The paths are the extensions' own and are not
# derived from the UUIDs - tilingshell@ferrarodomenico.com stores its settings
# under /org/gnome/shell/extensions/tilingshell/.
DCONF_SETTINGS=(
    "/org/gnome/shell/extensions/caffeine/|caffeine.ini"
    "/org/gnome/shell/extensions/tilingshell/|tiling-shell.ini"
)

TIMESTAMP="$(date +%Y%m%d%H%M%S)"

# The steps that could not be carried out, each with the command that does
# it by hand. The script records itself as complete only when this is empty
# - see the header.
INCOMPLETE=()

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# The dumps to load, next to this script; the backups go under the state
# directory common.sh keeps the completion markers in, like the ones
# setup-06-configs.sh takes.
DCONF_DIR="$SETUP_DIR/config/dconf"
DCONF_BACKUP_DIR="$STATE_DIR/gnome-extension-settings"

# Already-installed extensions are skipped. --force (or FORCE=1), parsed by
# setup_begin, re-downloads and reinstalls them, which also picks up a newer
# release.
setup_begin "$@"

# -----------------------------------------------------------------------------
# Verify the prerequisites
# -----------------------------------------------------------------------------
step "Install the GNOME extensions"
log "Verifying the prerequisites..."
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

# Extension Manager comes from setup-00-packages.sh; it is not needed to
# install the extensions, only to configure them afterwards, so this is a
# warning.
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
# Below every prerequisite and shell-version check. The loop can install
# one extension and then fail on the next, so the marker goes before it.
log "Installing the extensions..."
setup_invalidate

tmp_dir

# An installed extension is skipped only when its metadata.json lists the
# running shell version: a home directory restored from an older
# installation carries builds for the shell of that time, which the running
# one would refuse to load, and those are reinstalled like a missing one.
for uuid in "${EXTENSION_UUIDS[@]}"; do
    METADATA="$EXTENSIONS_DIR/$uuid/metadata.json"
    if [ -f "$METADATA" ] && [ "$FORCE" != "1" ] &&
        python3 -c '
import json, sys
metadata = json.load(open(sys.argv[1]))
sys.exit(0 if sys.argv[2] in map(str, metadata.get("shell-version", [])) else 1)
' "$METADATA" "$SHELL_MAJOR"; then
        log "$uuid is already installed for GNOME Shell $SHELL_MAJOR. Skipping (use --force to reinstall)."
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
    ZIP="$TMP_DIR/$uuid.shell-extension.zip"
    curl -fsSL -o "$ZIP" \
        "$EGO_URL/download-extension/$uuid.shell-extension.zip?version_tag=$VERSION_TAG"

    gnome-extensions install --force "$ZIP"

    log "Installed $uuid version $EXTENSION_VERSION."
done

# -----------------------------------------------------------------------------
# Enable the extensions
# -----------------------------------------------------------------------------
# "gnome-extensions enable" is not used: it first asks the running shell
# whether the extension exists, and a freshly unzipped extension is unknown to
# the shell until the next login, so it fails with "does not exist" and the
# extensions stayed disabled. Enabling is only the enabled-extensions key in
# org.gnome.shell, so that key is written directly - the shell reads it when
# it next starts. The UUIDs are appended to whatever is already enabled and
# dropped from disabled-extensions, which takes precedence over it.
#
# The write goes through dconf rather than gsettings set because gsettings
# exits 0 even when it could not reach dconf (see setup-00-packages.sh);
# without the session bus, as over SSH, the commands to run inside the
# desktop are printed instead.
log "Enabling the extensions..."
if command -v gsettings > /dev/null 2>&1 &&
    gsettings list-schemas 2> /dev/null | grep -x "org.gnome.shell" > /dev/null; then
    for key in enabled-extensions disabled-extensions; do
        CURRENT="$(gsettings get org.gnome.shell "$key")"

        # Prints the list with the UUIDs added (enabled) or removed
        # (disabled) as a GVariant literal, or nothing when it is unchanged.
        # The type prefix is always carried, because dconf cannot infer the
        # type of a bare [].
        WANTED="$(python3 -c "
import ast, sys
key, current = sys.argv[1], sys.argv[2]
uuids = sys.argv[3:]
items = ast.literal_eval(current.removeprefix('@as '))
if key == 'enabled-extensions':
    new = items + [u for u in uuids if u not in items]
else:
    new = [u for u in items if u not in uuids]
if new != items:
    print('@as [' + ', '.join(repr(u) for u in new) + ']')
" "$key" "$CURRENT" "${EXTENSION_UUIDS[@]}")"

        if [ -z "$WANTED" ]; then
            log "$key is already up to date."
        elif dconf write "/org/gnome/shell/$key" "$WANTED" 2> /dev/null; then
            log "Updated $key: ${WANTED#@as }"
        else
            log "Could not reach dconf. Inside a desktop session, run:"
            log "  gsettings set org.gnome.shell $key \"${WANTED#@as }\""
            INCOMPLETE+=("$key - inside a desktop session, run: gsettings set org.gnome.shell $key \"${WANTED#@as }\"")
        fi
    done
else
    log "No GNOME Shell schema found - the extensions were installed but not"
    log "enabled. After logging in, run:"
    for uuid in "${EXTENSION_UUIDS[@]}"; do
        log "  gnome-extensions enable $uuid"
        INCOMPLETE+=("enabling $uuid - after logging in, run: gnome-extensions enable $uuid")
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
log "Loading the extension settings..."
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

    if dconf load "$DCONF_PATH" < "$DUMP_FILE" 2> /dev/null; then
        log "Loaded $DUMP_NAME into $DCONF_PATH."
    else
        # The path is shell-quoted for the printed command, as the alias in
        # setup-01-devtools.sh is: a checkout under a directory with a space
        # would otherwise split when the line is pasted.
        log "Could not write $DCONF_PATH. Load it by hand with:"
        log "  dconf load $DCONF_PATH < $(printf '%q' "$DUMP_FILE")"
        INCOMPLETE+=("the settings in $DUMP_NAME - inside a desktop session, run: dconf load $DCONF_PATH < $(printf '%q' "$DUMP_FILE")")
    fi
done

# -----------------------------------------------------------------------------
# Verify the installation
# -----------------------------------------------------------------------------
log "Verifying the installation..."
for uuid in "${EXTENSION_UUIDS[@]}"; do
    METADATA="$EXTENSIONS_DIR/$uuid/metadata.json"
    if [ -f "$METADATA" ]; then
        INSTALLED="$(python3 -c '
import json, sys
print(json.load(open(sys.argv[1])).get("version", "unknown"))
' "$METADATA")"
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
# That is left to setup-06-configs.sh, the next script, which ends by logging
# out - so the extensions and the desktop settings arrive in one new session.
step "Log out to load the extensions"
log "The extensions load at the next login. setup-06-configs.sh, the next"
log "script, logs out when it is done - run it now and log back in after it."
log ""
log "After changing anything in Extension Manager, re-dump it into the repo"
log "so the next machine gets it - see the comment at the top of this script."

# Everything above has already been done either way - this only decides
# whether the script counts as done. Left unrecorded, it runs again on the
# next plain invocation and retries what was blocked; every step it performs
# is idempotent, so the repeat costs nothing.
if [ ${#INCOMPLETE[@]} -gt 0 ]; then
    echo >&2
    echo "Not everything could be set up:" >&2
    for item in "${INCOMPLETE[@]}"; do
        echo "  - $item" >&2
    done
    echo >&2
    echo "Fix the above, then run $0 again - it is NOT recorded as complete," >&2
    echo "so no --force is needed." >&2
    exit 0
fi

setup_end
