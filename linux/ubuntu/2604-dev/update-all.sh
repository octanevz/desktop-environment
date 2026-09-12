#!/bin/bash
set -euo pipefail

# =============================================================================
# This script performs the following tasks:
# - Runs update-sys.sh (apt packages and snaps)
# - Updates the .NET SDK and prunes the older SDKs and runtimes
# - Updates the global npm packages
# - Updates uv and the uv tools (Ruff)
# - Updates csharp-ls
# - Updates Claude Code
# - Updates the agent skills
# - Updates herdr
# - Updates the Oh My Zsh custom plugins
# - Updates lazygit, lazydocker, dive and yq
#
# Registered as the update-all alias by setup-01-devtools.sh.
# =============================================================================

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
sudo_keepalive

# -----------------------------------------------------------------------------
# Update the system packages
# -----------------------------------------------------------------------------
# Done by running update-sys.sh rather than repeating what it does, so the two
# stay in step. Resolved relative to this script, so it works no matter where
# it is called from.
step "Update the system packages"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/update-sys.sh"

# -----------------------------------------------------------------------------
# Update the .NET SDK
# -----------------------------------------------------------------------------
# setup-01-devtools.sh installs the SDK with dotnet-install.sh into ~/.dotnet,
# outside apt, so the same call is repeated here. It resolves the newest SDK
# of the channel and is a no-op when that version is already installed.
step "Update the .NET SDK"
DOTNET_CHANNEL="10.0"
DOTNET_ROOT="${DOTNET_ROOT:-$HOME/.dotnet}"
# Set in .zshrc by setup-01-devtools.sh; repeated here for a run from
# elsewhere.
export DOTNET_CLI_TELEMETRY_OPTOUT=1

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
step "Update the global npm packages"
log "Updating the global npm packages..."
npm update -g

# -----------------------------------------------------------------------------
# Update uv
# -----------------------------------------------------------------------------
# setup-01-devtools.sh installs it with the Astral installer, outside apt, and
# it replaces its own binary in place. Only the installer's build can do that -
# a uv from apt or pip refuses - so a failure here means uv came from somewhere
# else, and saying so beats aborting the rest of the updates.
step "Update uv"
log "Updating uv..."
uv self update || log "  Could not update uv - is it the one setup-01-devtools.sh installed?"

# The tools uv installed, which is Ruff and whatever has been added by hand
# since - they are versioned independently of uv itself and do not move with
# it. --all rather than naming Ruff, so a tool added later is not forgotten
# here.
log "Updating the uv tools..."
uv tool upgrade --all

# -----------------------------------------------------------------------------
# Update csharp-ls
# -----------------------------------------------------------------------------
# A .NET global tool, which apt knows nothing about.
step "Update csharp-ls"
log "Updating csharp-ls..."
dotnet tool update --global csharp-ls

# -----------------------------------------------------------------------------
# Update Claude Code
# -----------------------------------------------------------------------------
step "Update Claude Code"
log "Updating Claude Code..."
claude update

# -----------------------------------------------------------------------------
# Update the agent skills
# -----------------------------------------------------------------------------
# The skills setup-agents.sh installed globally with the skills
# CLI, for Claude Code, Codex and OpenCode alike. Run through npx like the
# install, so the CLI itself is always current too. Nothing to do until that
# script has been run, which the CLI reports rather than fails on.
step "Update the agent skills"
log "Updating the agent skills..."
npx -y skills update -g -y

# -----------------------------------------------------------------------------
# Update herdr
# -----------------------------------------------------------------------------
# A fast static-binary swap through its own updater.
step "Update herdr"
log "Updating herdr..."
herdr update

# -----------------------------------------------------------------------------
# Update the Oh My Zsh custom plugins
# -----------------------------------------------------------------------------
# setup-00-packages.sh clones them from GitHub. Oh My Zsh's own updater pulls
# the framework only and leaves custom/plugins alone, so they are pulled here.
step "Update the Oh My Zsh custom plugins"
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
# setup-01-devtools.sh installs it from its GitHub releases: it has no
# self-update and apt knows nothing about it.
#
# The installed version is compared first, so a run with nothing to do costs
# one API call instead of a 10 MB download. The match is anchored to the
# ", version=" field because "lazygit --version" also prints "git version=".
step "Update lazygit"
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

# -----------------------------------------------------------------------------
# Update lazydocker
# -----------------------------------------------------------------------------
# Installed by setup-01-devtools.sh from its GitHub releases, and updated the
# same way as lazygit above. "lazydocker --version" prints "Version: x.y.z"
# on its first line.
step "Update lazydocker"
LAZYDOCKER_LATEST="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazydocker/releases/latest |
    grep -Po '"tag_name": *"v\K[^"]*')"
LAZYDOCKER_INSTALLED="$(lazydocker --version | grep -Po '^Version: \K.*')"

if [ "$LAZYDOCKER_INSTALLED" = "$LAZYDOCKER_LATEST" ]; then
    log "lazydocker $LAZYDOCKER_INSTALLED is up to date."
else
    log "Updating lazydocker $LAZYDOCKER_INSTALLED -> $LAZYDOCKER_LATEST..."
    curl -fsSL -o /tmp/lazydocker.tar.gz "https://github.com/jesseduffield/lazydocker/releases/download/v${LAZYDOCKER_LATEST}/lazydocker_${LAZYDOCKER_LATEST}_Linux_x86_64.tar.gz"
    tar -C /tmp -xzf /tmp/lazydocker.tar.gz lazydocker
    sudo install -m 0755 /tmp/lazydocker /usr/local/bin/lazydocker
    rm -f /tmp/lazydocker.tar.gz /tmp/lazydocker
    lazydocker --version | head -1
fi

# -----------------------------------------------------------------------------
# Update dive
# -----------------------------------------------------------------------------
# Installed by setup-01-devtools.sh from its GitHub releases, and updated the
# same way as the two above. "dive --version" prints "dive 0.13.1".
step "Update dive"
DIVE_LATEST="$(curl -fsSL https://api.github.com/repos/wagoodman/dive/releases/latest |
    grep -Po '"tag_name": *"v\K[^"]*')"
DIVE_INSTALLED="$(dive --version | grep -Po '^dive \K.*')"

if [ "$DIVE_INSTALLED" = "$DIVE_LATEST" ]; then
    log "dive $DIVE_INSTALLED is up to date."
else
    log "Updating dive $DIVE_INSTALLED -> $DIVE_LATEST..."
    curl -fsSL -o /tmp/dive.tar.gz "https://github.com/wagoodman/dive/releases/download/v${DIVE_LATEST}/dive_${DIVE_LATEST}_linux_amd64.tar.gz"
    tar -C /tmp -xzf /tmp/dive.tar.gz dive
    sudo install -m 0755 /tmp/dive /usr/local/bin/dive
    rm -f /tmp/dive.tar.gz /tmp/dive
    dive --version
fi

# -----------------------------------------------------------------------------
# Update yq
# -----------------------------------------------------------------------------
# Installed by setup-01-devtools.sh from its GitHub releases, and updated the
# same way as the three above. "yq --version" prints the project URL before
# the version, hence the anchored match rather than a bare field.
step "Update yq"
YQ_LATEST="$(curl -fsSL https://api.github.com/repos/mikefarah/yq/releases/latest |
    grep -Po '"tag_name": *"v\K[^"]*')"
YQ_INSTALLED="$(yq --version | grep -Po 'version v\K.*')"

if [ "$YQ_INSTALLED" = "$YQ_LATEST" ]; then
    log "yq $YQ_INSTALLED is up to date."
else
    log "Updating yq $YQ_INSTALLED -> $YQ_LATEST..."
    curl -fsSL -o /tmp/yq "https://github.com/mikefarah/yq/releases/download/v${YQ_LATEST}/yq_linux_amd64"
    sudo install -m 0755 /tmp/yq /usr/local/bin/yq
    rm -f /tmp/yq
    yq --version
fi

log "Everything is up to date."
