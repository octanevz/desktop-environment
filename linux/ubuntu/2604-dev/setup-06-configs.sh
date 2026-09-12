#!/bin/bash
set -euo pipefail

# =============================================================================
# This script performs the following tasks:
# - Installs the tmux configuration and its plugins
# - Installs the Alacritty configuration and the theme it imports
# - Installs the herdr configuration
# - Installs the file-picker helper both multiplexers bind
# - Makes Alacritty the default terminal (Ctrl+Alt+T, "Open in Terminal")
# - Applies the GNOME desktop settings from config/dconf/gnome-settings.ini
# - Pins the installed applications to the GNOME dock
# - Logs out, on Enter, so the shell loads the extensions of setup-05
#
# Run this AFTER setup-00-packages.sh (tmux, Tmux Plugin Manager, fzf, fd,
# git), setup-01-devtools.sh (herdr) and setup-03-alacritty.sh (Alacritty,
# whose configuration and default-terminal entry are deployed here) - an
# order the completion markers enforce anyway. The Alacritty checks below
# are for a binary or desktop entry removed since, not for a script skipped.
#
# Nothing is ever overwritten in place: every file that already exists is
# copied to <name>.bak-<timestamp> before the new one is written, and the
# script reports exactly what it backed up. The same goes for the desktop
# settings: the previous value of every key that changes is saved to a file
# "dconf load /" can put back.
#
# The script records itself as complete only when nothing was left undone:
# a step that could not reach dconf - over SSH, say - or a plugin fetch that
# failed prints what to do by hand and leaves the marker unwritten, so the
# next plain run retries it without --force. This is the same rule
# setup-07-git.sh applies to an unauthenticated gh.
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
ALACRITTY_THEME_REPO="https://github.com/alacritty/alacritty-theme.git"

# Where the configuration files go: XDG_CONFIG_HOME with its default, the way
# setup-00-packages.sh places the atuin config and setup-04-lazyvim.sh the
# Neovim one. Alacritty, herdr and xdg-terminal-exec all look there first.
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# The theme clone is the one path that stays under $HOME/.config whatever
# XDG_CONFIG_HOME says: alacritty.toml imports it by that literal path, and
# Alacritty expands only "~" in an import, not environment variables.
ALACRITTY_THEME_DIR="$HOME/.config/alacritty/themes/alacritty-theme"

TIMESTAMP="$(date +%Y%m%d%H%M%S)"

# The steps that could not be carried out, each with what does it by hand.
# The script records itself as complete only when this is empty - see the
# header.
INCOMPLETE=()

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
setup_begin "$@"

# The files to install, next to this script.
CONFIG_DIR="$SETUP_DIR/config"

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
        INCOMPLETE+=("the tmux plugins - press prefix + I inside tmux, or re-run this script")
    fi
else
    log "  Tmux Plugin Manager is not installed - run setup-00-packages.sh,"
    log "  then press prefix + I inside tmux."
    INCOMPLETE+=("the tmux plugins - Tmux Plugin Manager is missing; re-run setup-00-packages.sh --force")
fi

# -----------------------------------------------------------------------------
# Install the Alacritty configuration
# -----------------------------------------------------------------------------
step "Configure Alacritty"
log "Installing the Alacritty configuration..."
install_config "$CONFIG_DIR/alacritty/alacritty.toml" \
    "$CONFIG_HOME/alacritty/alacritty.toml"

# The configuration imports a theme from this repository, so Alacritty fails to
# start without it. Cloned rather than vendored so themes can be switched by
# editing the import path alone, and left tracking master rather than pinned to
# a commit, so a --force re-run - and update-all.sh, which pulls it too -
# picks up themes added upstream.
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
# Make Alacritty the default terminal
# -----------------------------------------------------------------------------
# Ubuntu 26.04 no longer names the terminal in a gsettings key: Ctrl+Alt+T
# (Ubuntu's gnome-settings-daemon patch), "Open in Terminal" and Terminal=true
# desktop entries all go through xdg-terminal-exec, which picks the first
# installed entry in the xdg-terminals.list files - ~/.config first, then
# Ubuntu's own list in /usr/share/xdg-terminal-exec/, where Ptyxis comes first.
# Writing the user file is the whole change; nothing is written to dconf.
#
# Alacritty's desktop entry has the TerminalEmulator category the spec asks
# for and no X-TerminalArgExec, for which xdg-terminal-exec assumes "-e" -
# which is what Alacritty takes.
log "Installing the xdg-terminal-exec terminal list..."
install_config "$CONFIG_DIR/xdg-terminals.list" "$CONFIG_HOME/xdg-terminals.list"

if command -v xdg-terminal-exec > /dev/null 2>&1; then
    if [ -f /usr/local/share/applications/Alacritty.desktop ]; then
        log "  Ctrl+Alt+T and \"Open in Terminal\" now open Alacritty."
    else
        log "  Alacritty's desktop entry is missing - re-run setup-03-alacritty.sh"
        log "  with --force; the list takes effect as soon as the entry exists."
    fi
else
    log "  xdg-terminal-exec is not installed - the list is in place for when"
    log "  it is."
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
install_config "$CONFIG_DIR/herdr/config.toml" "$CONFIG_HOME/herdr/config.toml"

if command -v herdr > /dev/null 2>&1; then
    if herdr config check > /dev/null 2>&1; then
        log "  herdr config check: ok."
    else
        # The file is in place but herdr rejects it - a key it no longer
        # knows, most likely. Fixable in the repo, so it is retried by a plain
        # re-run rather than recorded as done, like an unauthenticated gh in
        # setup-07-git.sh.
        log "  herdr config check failed - run it by hand to see why."
        INCOMPLETE+=("the herdr configuration - 'herdr config check' rejects it; fix config/herdr/config.toml, then re-run this script")
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
step "Configure GNOME"
GNOME_SETTINGS="$CONFIG_DIR/dconf/gnome-settings.ini"
# Under the state directory common.sh keeps the completion markers in, like
# the dock backup below and the one setup-05-gnome-extensions.sh takes.
GNOME_SETTINGS_BACKUP="$STATE_DIR/gnome-settings/gnome-settings.ini.bak-$TIMESTAMP"

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

    # Backed up BEFORE the write, so a backup that cannot be written (set -e
    # stops the script on it) never leaves a changed key without its old
    # value. A key that was never set has nothing to put back, and is not
    # backed up; "dconf reset" is how to unset it again. Should the write
    # below then fail, the backup carries a value that never changed, which
    # is harmless - loading it back is a no-op.
    if [ -n "$current" ]; then
        mkdir -p "$(dirname "$GNOME_SETTINGS_BACKUP")"
        if [ -n "$BACKUP_SECTION" ]; then
            printf '%s\n' "$BACKUP_SECTION" >> "$GNOME_SETTINGS_BACKUP"
            BACKUP_SECTION=""
        fi
        printf '%s=%s\n' "$key" "$current" >> "$GNOME_SETTINGS_BACKUP"
    fi

    if ! dconf write "$DCONF_PATH$key" "$wanted" 2> /dev/null; then
        UNREACHABLE=1
        continue
    fi

    log "  $DCONF_PATH$key: ${current:-<unset>} -> $wanted"
    CHANGED=$((CHANGED + 1))
done < "$GNOME_SETTINGS"

if [ "$UNREACHABLE" = "1" ]; then
    # The path is shell-quoted for the printed command, as the alias in
    # setup-01-devtools.sh is: a checkout under a directory with a space
    # would otherwise split when the line is pasted.
    log "  Could not reach dconf. Inside a desktop session, run:"
    log "    grep -v '^#' $(printf '%q' "$GNOME_SETTINGS") | dconf load /"
    INCOMPLETE+=("the GNOME settings - inside a desktop session, run: grep -v '^#' $(printf '%q' "$GNOME_SETTINGS") | dconf load /")
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
# edit it to taste. Only entries whose .desktop file exists are pinned, so a
# program that is missing leaves no dead icon behind. JetBrains Toolbox writes
# its .desktop file on its first launch, not at install, so its icon appears
# only after a re-run of this script with --force (the completion marker
# stops a plain re-run).
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
# file this script touches, and an unchanged dock is left alone. The write
# goes through dconf rather than gsettings set because gsettings exits 0 even
# when it could not reach dconf (see setup-00-packages.sh); without the
# session bus, as over SSH, the command to run inside the desktop is printed
# instead.
if command -v gsettings > /dev/null 2>&1 &&
    gsettings list-schemas 2> /dev/null | grep -x "org.gnome.shell" > /dev/null; then
    # gsettings get prints an empty list as "@as []" and a populated one
    # without the type prefix, so the prefix is stripped for the comparison;
    # the write always carries it, because dconf cannot infer the type of a
    # bare [].
    CURRENT_FAVORITES="$(gsettings get org.gnome.shell favorite-apps)"
    if [ "${CURRENT_FAVORITES#@as }" = "[$FAVORITES]" ]; then
        log "  Dock is already up to date."
    else
        DOCK_BACKUP="$STATE_DIR/gnome-dock/favorite-apps.bak-$TIMESTAMP"
        mkdir -p "$(dirname "$DOCK_BACKUP")"
        printf '%s\n' "$CURRENT_FAVORITES" > "$DOCK_BACKUP"
        log "  Backed up the previous dock -> $DOCK_BACKUP"
        if dconf write /org/gnome/shell/favorite-apps "@as [$FAVORITES]" 2> /dev/null; then
            log "  Dock: $FAVORITES"
        else
            log "  Could not reach dconf. Inside a desktop session, run:"
            log "    gsettings set org.gnome.shell favorite-apps \"[$FAVORITES]\""
            INCOMPLETE+=("the dock - inside a desktop session, run: gsettings set org.gnome.shell favorite-apps \"[$FAVORITES]\"")
        fi
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
log "The GNOME settings are applied at once; the running desktop picks them up."

# Everything above has already been done either way - this only decides
# whether the script counts as done. Left unrecorded, it runs again on the
# next plain invocation and retries what was blocked; every step it performs
# is idempotent, so the repeat costs nothing. The log-out below still
# follows, since the extensions from setup-05 need it either way.
if [ ${#INCOMPLETE[@]} -gt 0 ]; then
    echo >&2
    echo "Not everything could be set up:" >&2
    for item in "${INCOMPLETE[@]}"; do
        echo "  - $item" >&2
    done
    echo >&2
    echo "Fix the above, then run $0 again - it is NOT recorded as complete," >&2
    echo "so no --force is needed." >&2
else
    setup_end
fi

# -----------------------------------------------------------------------------
# Log out to load the extensions
# -----------------------------------------------------------------------------
# Not for this script's own changes - those are live already - but for the
# extensions setup-05-gnome-extensions.sh installed: the shell only loads a
# new extension at login, and on Wayland (the Ubuntu 26.04 default) there is
# no shell restart, so the session has to end. Doing it here rather than
# there lets both scripts run in one go.
#
# Not a question, as with the reboots in setup-00 and setup-01: Enter logs
# out; Ctrl-C is the way out for whoever wants to log out later - the
# completion marker, when earned, is written already. Without a session bus,
# as over SSH, gnome-session-quit cannot reach the session, so only the note
# is printed.
step "Log out to load the extensions"
log "The session has to end for the GNOME extensions from the previous script"
log "to load - on Wayland a full log out; restarting the shell is not enough."
log "Continue with setup-07-git.sh from a new terminal after logging back in."
log ""
if [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] &&
    command -v gnome-session-quit > /dev/null 2>&1; then
    read -r -p "Press Enter to log out..."
    echo "Logging out..."
    exec gnome-session-quit --logout --no-prompt
else
    log "Log out and log back in."
fi
