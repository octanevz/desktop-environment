#!/bin/bash
set -euo pipefail

# =============================================================================
# This script performs the following tasks:
# - Installs the tmux configuration and its plugins
# - Installs the Alacritty configuration and the theme it imports
# - Installs the herdr configuration
# - Installs the file-picker helper both multiplexers bind
# - Pins the installed applications to the GNOME dock
#
# Run this AFTER setup_0_packages.sh (tmux, Tmux Plugin Manager, fzf, fd, git,
# the JetBrains Mono font) and setup_1_devtools.sh (herdr). setup_5 installs
# Alacritty itself, but the configuration is deployed here whether or not you
# ran it - a config for a program that is not installed is harmless.
#
# Nothing is ever overwritten in place: every file that already exists is
# copied to <name>.bak-<timestamp> before the new one is written, and the
# script reports exactly what it backed up.
# =============================================================================

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/config"

ALACRITTY_THEME_REPO="https://github.com/alacritty/alacritty-theme.git"
ALACRITTY_THEME_DIR="$HOME/.config/alacritty/themes/alacritty-theme"

TIMESTAMP="$(date +%Y%m%d%H%M%S)"

log() {
    echo -e "\e[32m$1\e[0m"
}

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

# -----------------------------------------------------------------------------
# Install the file picker
# -----------------------------------------------------------------------------
# Both tmux and herdr bind this, so it goes in first. It needs fzf and fd,
# which setup_0_packages.sh installs.
log "Installing the file picker..."
install_config "$CONFIG_DIR/bin/file-picker" "$HOME/.local/bin/file-picker"
chmod +x "$HOME/.local/bin/file-picker"

# -----------------------------------------------------------------------------
# Install the tmux configuration
# -----------------------------------------------------------------------------
log "Installing the tmux configuration..."
install_config "$CONFIG_DIR/tmux.conf" "$HOME/.tmux.conf"

# TPM is cloned by setup_0_packages.sh, but it only fetches the plugins the
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
    log "  Tmux Plugin Manager is not installed - run setup_0_packages.sh,"
    log "  then press prefix + I inside tmux."
fi

# -----------------------------------------------------------------------------
# Install the Alacritty configuration
# -----------------------------------------------------------------------------
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
# Pin the applications to the dock
# -----------------------------------------------------------------------------
# The dock shows org.gnome.shell favorite-apps, in list order. The list below
# REPLACES the Ubuntu default set (Firefox, Thunderbird, App Center and so on);
# edit it to taste. Only entries whose .desktop file exists are pinned, so an
# optional script that was not run leaves no dead icon behind - re-run this
# script after it to add the icon. JetBrains Toolbox writes its .desktop file
# on its first launch, not at install, so it too appears after a re-run.
DOCK_FAVORITES=(
    org.gnome.Nautilus.desktop # Files
    Alacritty.desktop          # setup_5_alacritty.sh
    code.desktop               # Visual Studio Code
    orca-ide.desktop           # Orca ADE
    jetbrains-toolbox.desktop  # setup_3_jetbrains_toolbox.sh, after first launch
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

# gsettings needs the session bus, as in setup_0_packages.sh: over SSH it
# cannot write, so the command to run inside the desktop is printed instead.
if command -v gsettings > /dev/null 2>&1 &&
    gsettings list-schemas 2> /dev/null | grep -qx "org.gnome.shell"; then
    if gsettings set org.gnome.shell favorite-apps "[$FAVORITES]" 2> /dev/null; then
        log "  Dock: $FAVORITES"
    else
        log "  Could not reach dconf. Inside a desktop session, run:"
        log "    gsettings set org.gnome.shell favorite-apps \"[$FAVORITES]\""
    fi
else
    log "  No GNOME Shell schema found - skipping the dock."
fi

# -----------------------------------------------------------------------------
# Verify the installation
# -----------------------------------------------------------------------------
log "Configuration files installed successfully!"
log "Reload tmux with: tmux source-file ~/.tmux.conf"
log "Alacritty and herdr pick their configuration up on the next start."
