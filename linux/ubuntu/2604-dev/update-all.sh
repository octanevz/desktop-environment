#!/bin/bash
set -euo pipefail

# =============================================================================
# This script performs the following tasks:
# - Runs update-sys.sh (apt packages and snaps)
# - Updates the .NET SDK and prunes the older SDKs and runtimes
# - Updates the global npm packages
# - Updates csharp-ls
# - Updates Claude Code
# - Updates the agent skills
# - Updates herdr
# - Updates the Oh My Zsh custom plugins
# - Updates lazygit
#
# Registered as the update-all alias by setup-01-devtools.sh.
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
# setup-01-devtools.sh installs the SDK with dotnet-install.sh into ~/.dotnet,
# outside apt, so the same call is repeated here. It resolves the newest SDK
# of the channel and is a no-op when that version is already installed.
DOTNET_CHANNEL="10.0"
DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"

log "Updating the .NET SDK..."
curl -fsSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel "$DOTNET_CHANNEL"
dotnet --version

# The installer adds the new version next to the old ones and never removes
# anything, so every versioned directory under ~/.dotnet is pruned to its
# newest entry: the SDKs, the shared runtimes (Microsoft.NETCore.App and
# Microsoft.AspNetCore.App), the host resolver, the targeting packs and the
# templates. Only ~/.dotnet is touched - an SDK from apt lives elsewhere.
# Note that a project whose global.json pins an older SDK would stop
# building after this; none here do.
prune_versions() {
    local dir="$1"
    [ -d "$dir" ] || return 0
    local versions
    versions="$(find "$dir" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -V)"
    [ -n "$versions" ] || return 0
    local newest
    newest="$(printf '%s\n' "$versions" | tail -n 1)"
    local version
    while IFS= read -r version; do
        [ "$version" = "$newest" ] && continue
        rm -rf "${dir:?}/$version"
        log "  Removed ${dir#"$DOTNET_ROOT/"}/$version (kept $newest)."
    done <<< "$versions"
}

log "Pruning the older .NET SDKs and runtimes..."
prune_versions "$DOTNET_ROOT/sdk"
prune_versions "$DOTNET_ROOT/host/fxr"
prune_versions "$DOTNET_ROOT/templates"
for dir in "$DOTNET_ROOT"/shared/*/ "$DOTNET_ROOT"/packs/*/; do
    [ -d "$dir" ] && prune_versions "${dir%/}"
done

# -----------------------------------------------------------------------------
# Update the global npm packages
# -----------------------------------------------------------------------------
# Codex CLI, the language servers and the rest of what setup-01-devtools.sh
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
# Update the agent skills
# -----------------------------------------------------------------------------
# The skills setup-agents.sh installed globally with the skills
# CLI, for Claude Code, Codex and OpenCode alike. Run through npx like the
# install, so the CLI itself is always current too. Nothing to do until that
# script has been run, which the CLI reports rather than fails on.
log "Updating the agent skills..."
npx -y skills update -g -y

# -----------------------------------------------------------------------------
# Update herdr
# -----------------------------------------------------------------------------
# A fast static-binary swap through its own updater.
log "Updating herdr..."
herdr update

# -----------------------------------------------------------------------------
# Update the Oh My Zsh custom plugins
# -----------------------------------------------------------------------------
# setup-00-packages.sh clones them from GitHub. Oh My Zsh's own updater pulls
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
        log "$plugin is not installed - run setup-00-packages.sh."
    fi
done

# -----------------------------------------------------------------------------
# Update lazygit
# -----------------------------------------------------------------------------
# setup-00-packages.sh installs it from its GitHub releases: it has no
# self-update and apt knows nothing about it.
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
