#!/bin/bash
set -euo pipefail

# =============================================================================
# This script performs the following tasks:
# - Installs the tmux configuration and its plugins
# - Installs the Alacritty configuration and the theme it imports
# - Installs the herdr configuration
# - Installs the file-picker helper both multiplexers bind
# - Applies the GNOME desktop settings from config/dconf/gnome-settings.ini
# - Pins the installed applications to the GNOME dock
#
# Run this AFTER setup-00-packages.sh (tmux, Tmux Plugin Manager, fzf, fd, git,
# the JetBrains Mono font) and setup-01-devtools.sh (herdr). setup-04 installs
# Alacritty itself, but the configuration is deployed here whether or not you
# ran it - a config for a program that is not installed is harmless.
#
# Nothing is ever overwritten in place: every file that already exists is
# copied to <name>.bak-<timestamp> before the new one is written, and the
# script reports exactly what it backed up. The same goes for the desktop
# settings: the previous value of every key that changes is saved to a file
# "dconf load /" can put back.
#
# To capture your own desktop settings, change them in Settings or Tweaks
# and dump them on the machine:
#
#   dconf dump / > gnome-settings-dump.ini
#
# then paste the sections you mean to keep into config/dconf/gnome-settings.ini
# - the dump also holds window sizes, timestamps and other state the desktop
# rewrites on its own, which does not belong in the repo.
# =============================================================================

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"

ALACRITTY_THEME_REPO="https://github.com/alacritty/alacritty-theme.git"
ALACRITTY_THEME_DIR="$HOME/.config/alacritty/themes/alacritty-theme"

TIMESTAMP="$(date +%Y%m%d%H%M%S)"

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
setup_begin "$@"

# -----------------------------------------------------------------------------
# Install one configuration file
# -----------------------------------------------------------------------------
# Backs up whatever is already there, then copies the repo's version in. An
# identical file is left alone so that re-running does not produce a pile of
# backups that are all the same.
install_config() {
    local source=$1 target=$2

    if [ ! -f "$source" ]; then
        echo "Missing $source - is the repo complete?" >&2
        exit 1
    fi

    mkdir -p "$(dirname "$target")"

    if [ -f "$target" ]; then
        if cmp -s "$source" "$target"; then
            log "  $target is already up to date."
            return
        fi
        cp -p "$target" "$target.bak-$TIMESTAMP"
        log "  Backed up $target -> $target.bak-$TIMESTAMP"
    fi

    cp "$source" "$target"
    log "  Installed $target"
}

# Nothing above changes the machine - only the helper definitions - and the
# first install_config call is just below.
setup_invalidate

# -----------------------------------------------------------------------------
# Install the file picker
# -----------------------------------------------------------------------------
# Both tmux and herdr bind this, so it goes in first. It needs fzf and fd,
# which setup-00-packages.sh installs.
step "Install the file picker"
log "Installing the file picker..."
install_config "$CONFIG_DIR/bin/file-picker" "$HOME/.local/bin/file-picker"
chmod +x "$HOME/.local/bin/file-picker"

# -----------------------------------------------------------------------------
# Install the tmux configuration
# -----------------------------------------------------------------------------
step "Install the tmux configuration"
log "Installing the tmux configuration..."
install_config "$CONFIG_DIR/tmux.conf" "$HOME/.tmux.conf"

# TPM is cloned by setup-00-packages.sh, but it only fetches the plugins the
# configuration declares. install_plugins is TPM's own non-interactive entry
# point and is safe to re-run - it skips what is already cloned.
TPM_INSTALL="$HOME/.tmux/plugins/tpm/bin/install_plugins"
if [ -x "$TPM_INSTALL" ]; then
    log "Installing the tmux plugins..."
    if "$TPM_INSTALL" > /dev/null 2>&1; then
        log "  tmux plugins installed."
    else
        log "  TPM reported a problem - press prefix + I inside tmux to retry."
    fi
else
    log "  Tmux Plugin Manager is not installed - run setup-00-packages.sh,"
    log "  then press prefix + I inside tmux."
fi

# -----------------------------------------------------------------------------
# Install the Alacritty configuration
# -----------------------------------------------------------------------------
step "Install the Alacritty configuration"
log "Installing the Alacritty configuration..."
install_config "$CONFIG_DIR/alacritty/alacritty.toml" \
    "$HOME/.config/alacritty/alacritty.toml"

# The configuration imports a theme from this repository, so Alacritty fails to
# start without it. Cloned rather than vendored so themes can be switched by
# editing the import path alone, and left tracking master rather than pinned to
# a commit, so re-running picks up themes added upstream.
if [ -d "$ALACRITTY_THEME_DIR/.git" ]; then
    THEME_BEFORE="$(git -C "$ALACRITTY_THEME_DIR" rev-parse --short HEAD)"
    git -C "$ALACRITTY_THEME_DIR" pull --ff-only --quiet
    THEME_AFTER="$(git -C "$ALACRITTY_THEME_DIR" rev-parse --short HEAD)"

    if [ "$THEME_BEFORE" = "$THEME_AFTER" ]; then
        log "  Alacritty themes are already up to date ($THEME_AFTER)."
    else
        log "  Updated the Alacritty themes ($THEME_BEFORE -> $THEME_AFTER)."
    fi
else
    log "Cloning the Alacritty themes..."
    git clone --quiet "$ALACRITTY_THEME_REPO" "$ALACRITTY_THEME_DIR"
    log "  Cloned at $(git -C "$ALACRITTY_THEME_DIR" rev-parse --short HEAD)."
fi

# Fail loudly rather than leaving a configuration that cannot start.
if [ ! -f "$ALACRITTY_THEME_DIR/themes/horizon_dark.toml" ]; then
    echo "The horizon_dark theme is missing from $ALACRITTY_THEME_DIR." >&2
    echo "alacritty.toml imports it and Alacritty will not start without it." >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# Install the herdr configuration
# -----------------------------------------------------------------------------
# This is a complete config.toml rather than a merge: it carries the settings
# herdr writes itself (onboarding, theme, ui) plus a [keys] section that maps
# herdr onto the same keys as tmux.conf. An existing file is backed up, so
# anything changed on this machine is recoverable from the backup.
#
# Two of the bindings deliberately differ from tmux, because herdr rejects the
# tokens tmux uses: | is written shift+backslash, and copy mode is prefix+[
# rather than PageUp, which herdr has no key name for.
step "Install the herdr configuration"
log "Installing the herdr configuration..."
install_config "$CONFIG_DIR/herdr/config.toml" "$HOME/.config/herdr/config.toml"

if command -v herdr > /dev/null 2>&1; then
    if herdr config check > /dev/null 2>&1; then
        log "  herdr config check: ok."
    else
        log "  herdr config check failed - run it by hand to see why."
    fi
fi

# -----------------------------------------------------------------------------
# Apply the GNOME settings
# -----------------------------------------------------------------------------
# gnome-settings.ini is in "dconf dump" format: a [section] per dconf path and
# a key=value line per key. It is applied key by key rather than with one
# "dconf load /", so that the script can tell which keys actually change,
# back up exactly those, and leave an up-to-date desktop alone. "dconf read"
# prints a value in the same GVariant notation the dump uses, so a plain
# string comparison decides.
#
# Comments in the file are the script's own convention; dconf would not
# accept them in a load, which is another reason the keys are written one at
# a time. The backup is written without them, in load format, so it can be
# put back with "dconf load / < <backup>".
#
# dconf read works from the database file alone, but writing needs the dconf
# service on the session bus, which is not there over SSH. The first failed
# write ends the loop with the command to run inside the desktop instead.
step "Apply the GNOME settings"
GNOME_SETTINGS="$CONFIG_DIR/dconf/gnome-settings.ini"
GNOME_SETTINGS_BACKUP="$HOME/.local/state/gnome-settings/gnome-settings.ini.bak-$TIMESTAMP"

if [ ! -f "$GNOME_SETTINGS" ]; then
    echo "Missing $GNOME_SETTINGS - is the repo complete?" >&2
    exit 1
fi

if ! command -v dconf > /dev/null 2>&1; then
    echo "dconf was not found. setup-00-packages.sh installs dconf-cli - run" >&2
    echo "that first, then re-run this script." >&2
    exit 1
fi

log "Applying the GNOME settings..."
DCONF_PATH=""
BACKUP_SECTION=""
CHANGED=0
UNREACHABLE=0
while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
        "" | "#"*)
            continue
            ;;
        "["*"]")
            DCONF_PATH="${line#[}"
            DCONF_PATH="/${DCONF_PATH%]}/"
            BACKUP_SECTION="$line"
            continue
            ;;
    esac

    key="${line%%=*}"
    wanted="${line#*=}"
    current="$(dconf read "$DCONF_PATH$key")"

    if [ "$current" = "$wanted" ]; then
        continue
    fi

    if [ "$UNREACHABLE" = "1" ]; then
        continue
    fi

    if ! dconf write "$DCONF_PATH$key" "$wanted" 2> /dev/null; then
        UNREACHABLE=1
        continue
    fi

    # A key that was never set has nothing to put back, and is not backed
    # up; "dconf reset" is how to unset it again.
    if [ -n "$current" ]; then
        mkdir -p "$(dirname "$GNOME_SETTINGS_BACKUP")"
        if [ -n "$BACKUP_SECTION" ]; then
            printf '%s\n' "$BACKUP_SECTION" >> "$GNOME_SETTINGS_BACKUP"
            BACKUP_SECTION=""
        fi
        printf '%s=%s\n' "$key" "$current" >> "$GNOME_SETTINGS_BACKUP"
    fi

    log "  $DCONF_PATH$key: ${current:-<unset>} -> $wanted"
    CHANGED=$((CHANGED + 1))
done < "$GNOME_SETTINGS"

if [ "$UNREACHABLE" = "1" ]; then
    log "  Could not reach dconf. Inside a desktop session, run:"
    log "    grep -v '^#' $GNOME_SETTINGS | dconf load /"
elif [ "$CHANGED" = "0" ]; then
    log "  GNOME settings are already up to date."
else
    if [ -f "$GNOME_SETTINGS_BACKUP" ]; then
        log "  Backed up the previous values -> $GNOME_SETTINGS_BACKUP"
    fi
    log "  Changed $CHANGED GNOME settings."
fi

# -----------------------------------------------------------------------------
# Pin the applications to the dock
# -----------------------------------------------------------------------------
# The dock shows org.gnome.shell favorite-apps, in list order. The list below
# REPLACES the Ubuntu default set (Firefox, Thunderbird, App Center and so on);
# edit it to taste. Only entries whose .desktop file exists are pinned, so an
# optional script that was not run leaves no dead icon behind - re-run this
# script after it to add the icon. JetBrains Toolbox writes its .desktop file
# on its first launch, not at install, so it too appears after a re-run.
step "Pin the applications to the dock"
DOCK_FAVORITES=(
    org.gnome.Nautilus.desktop # Files
    Alacritty.desktop          # setup-03-alacritty.sh
    code.desktop               # Visual Studio Code
    orca-ide.desktop           # Orca ADE
    jetbrains-toolbox.desktop  # setup-01-devtools.sh, after first launch
    google-chrome.desktop
    gimp.desktop
    org.gnome.Settings.desktop
)

# Where .desktop files live: the user's own, then the system directories
# (/usr/local/share for Alacritty, /usr/share for packages) and the snap dir,
# which is on XDG_DATA_DIRS inside a session but not over SSH.
APPLICATION_DIRS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
IFS=: read -r -a data_dirs <<< "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
for dir in "${data_dirs[@]}" /var/lib/snapd/desktop; do
    APPLICATION_DIRS="$APPLICATION_DIRS:$dir/applications"
done

log "Pinning the installed applications to the dock..."
FAVORITES=""
for app in "${DOCK_FAVORITES[@]}"; do
    found=0
    IFS=: read -r -a app_dirs <<< "$APPLICATION_DIRS"
    for dir in "${app_dirs[@]}"; do
        if [ -f "$dir/$app" ]; then
            found=1
            break
        fi
    done

    if [ "$found" = "1" ]; then
        FAVORITES="$FAVORITES${FAVORITES:+, }'$app'"
    else
        log "  $app is not installed - not pinned."
    fi
done

# The previous favourites are saved before they are replaced, like every other
# file this script touches, and an unchanged dock is left alone. The write goes
# through dconf rather than gsettings set because gsettings exits 0 even when it
# could not reach dconf (see setup-00-packages.sh); without the session bus, as
# over SSH, the command to run inside the desktop is printed instead.
if command -v gsettings > /dev/null 2>&1 &&
    gsettings list-schemas 2> /dev/null | grep -x "org.gnome.shell" > /dev/null; then
    # gsettings get prints an empty list as "@as []" and a populated one without
    # the type prefix, so the prefix is stripped for the comparison; the write
    # always carries it, because dconf cannot infer the type of a bare [].
    CURRENT_FAVORITES="$(gsettings get org.gnome.shell favorite-apps)"
    if [ "${CURRENT_FAVORITES#@as }" = "[$FAVORITES]" ]; then
        log "  Dock is already up to date."
    else
        DOCK_BACKUP="$HOME/.local/state/gnome-dock/favorite-apps.bak-$TIMESTAMP"
        mkdir -p "$(dirname "$DOCK_BACKUP")"
        printf '%s\n' "$CURRENT_FAVORITES" > "$DOCK_BACKUP"
        log "  Backed up the previous dock -> $DOCK_BACKUP"
        if dconf write /org/gnome/shell/favorite-apps "@as [$FAVORITES]" 2> /dev/null; then
            log "  Dock: $FAVORITES"
        else
            log "  Could not reach dconf. Inside a desktop session, run:"
            log "    gsettings set org.gnome.shell favorite-apps \"[$FAVORITES]\""
        fi
    fi
else
    log "  No GNOME Shell schema found - skipping the dock."
fi

# -----------------------------------------------------------------------------
# Verify the installation
# -----------------------------------------------------------------------------
step "Verify the installation"
log "Configuration files installed successfully!"
log "Reload tmux with: tmux source-file ~/.tmux.conf"
log "Alacritty and herdr pick their configuration up on the next start."
log "The GNOME settings are applied at once; the running desktop picks them up."

setup_end
