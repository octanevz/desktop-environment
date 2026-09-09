#!/bin/bash
set -euo pipefail

# =============================================================================
# This script performs the following tasks:
# - Runs update-sys.sh (apt packages and snaps)
# - Updates the .NET SDK
# - Updates the global npm packages
# - Updates csharp-ls
# - Updates Claude Code
# - Updates herdr
# - Updates the Oh My Zsh custom plugins
# - Updates lazygit
#
# Registered as the update-all alias by setup_1_devtools.sh. Deliberately NOT
# updated here: Neovim (see below) and Alacritty (a source build, see
# setup_5_alacritty.sh), so that routine updates stay fast and predictable.
# =============================================================================

log() {
    echo -e "\e[32m$1\e[0m"
}

# -----------------------------------------------------------------------------
# Update the system packages
# -----------------------------------------------------------------------------
# Done by running update-sys.sh rather than repeating what it does, so the two
# stay in step. Resolved relative to this script, so it works no matter where
# it is called from.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/update-sys.sh"

# -----------------------------------------------------------------------------
# Update the .NET SDK
# -----------------------------------------------------------------------------
# setup_1_devtools.sh installs the SDK with dotnet-install.sh into ~/.dotnet,
# outside apt, so the same call is repeated here. It resolves the newest SDK
# of the channel and is a no-op when that version is already installed.
# Older SDKs and runtimes are left in place next to the new one - remove them
# from ~/.dotnet/sdk and ~/.dotnet/shared by hand if they pile up.
DOTNET_CHANNEL="10.0"

log "Updating the .NET SDK..."
curl -fsSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel "$DOTNET_CHANNEL"
dotnet --version

# -----------------------------------------------------------------------------
# Update the global npm packages
# -----------------------------------------------------------------------------
# Codex CLI, the language servers and the rest of what setup_1_devtools.sh
# installs with npm.
log "Updating the global npm packages..."
npm update -g

# -----------------------------------------------------------------------------
# Update csharp-ls
# -----------------------------------------------------------------------------
# A .NET global tool, which apt knows nothing about.
log "Updating csharp-ls..."
dotnet tool update --global csharp-ls

# -----------------------------------------------------------------------------
# Update Claude Code
# -----------------------------------------------------------------------------
log "Updating Claude Code..."
claude update

# -----------------------------------------------------------------------------
# Update herdr
# -----------------------------------------------------------------------------
# A fast static-binary swap through its own updater.
log "Updating herdr..."
herdr update

# -----------------------------------------------------------------------------
# Update the Oh My Zsh custom plugins
# -----------------------------------------------------------------------------
# setup_0_packages.sh clones them from GitHub. Oh My Zsh's own updater pulls
# the framework only and leaves custom/plugins alone, so they are pulled here.
for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
    PLUGIN_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/$plugin"
    if [ -d "$PLUGIN_DIR/.git" ]; then
        PLUGIN_BEFORE="$(git -C "$PLUGIN_DIR" rev-parse --short HEAD)"
        git -C "$PLUGIN_DIR" pull --ff-only --quiet
        PLUGIN_AFTER="$(git -C "$PLUGIN_DIR" rev-parse --short HEAD)"
        if [ "$PLUGIN_BEFORE" = "$PLUGIN_AFTER" ]; then
            log "$plugin is up to date ($PLUGIN_AFTER)."
        else
            log "Updated $plugin ($PLUGIN_BEFORE -> $PLUGIN_AFTER)."
        fi
    else
        log "$plugin is not installed - run setup_0_packages.sh."
    fi
done

# -----------------------------------------------------------------------------
# Update lazygit
# -----------------------------------------------------------------------------
# setup_0_packages.sh installs it from its GitHub releases: it has no
# self-update and apt knows nothing about it. Neovim is installed the same way
# but is deliberately NOT updated here - a surprise Neovim bump can break
# LazyVim plugins, so re-run setup_0_packages.sh when you want it moved.
#
# The installed version is compared first, so a run with nothing to do costs
# one API call instead of a 10 MB download. The match is anchored to the
# ", version=" field because "lazygit --version" also prints "git version=".
LAZYGIT_LATEST="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest |
    grep -Po '"tag_name": *"v\K[^"]*')"
LAZYGIT_INSTALLED="$(lazygit --version | grep -Po ', version=\K[^,]*')"

if [ "$LAZYGIT_INSTALLED" = "$LAZYGIT_LATEST" ]; then
    log "lazygit $LAZYGIT_INSTALLED is up to date."
else
    log "Updating lazygit $LAZYGIT_INSTALLED -> $LAZYGIT_LATEST..."
    curl -fsSL -o /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_LATEST}/lazygit_${LAZYGIT_LATEST}_Linux_x86_64.tar.gz"
    tar -C /tmp -xzf /tmp/lazygit.tar.gz lazygit
    sudo install -m 0755 /tmp/lazygit /usr/local/bin/lazygit
    rm -f /tmp/lazygit.tar.gz /tmp/lazygit
    lazygit --version
fi

log "Everything is up to date."
