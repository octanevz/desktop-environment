#!/bin/bash
set -euo pipefail

# =============================================================================
# This script performs the following tasks:
# - Runs update-sys.sh (apt packages and snaps)
# - Updates the .NET SDK and prunes the older SDKs and runtimes
# - Updates Node.js 24, carrying the global packages over to the new version
# - Updates the global npm packages
# - Updates uv and the uv tools (Ruff)
# - Updates csharp-ls
# - Updates Claude Code
# - Updates the agent skills
# - Updates herdr
# - Updates the Oh My Zsh custom plugins, Tmux Plugin Manager and the tmux
#   plugins, and the Alacritty themes - the git clones the setup scripts make
# - Updates lazygit, lazydocker, dive and yq
# - Regenerates the Zsh completions of yq, uv, uvx, Ruff and herdr, so they
#   never lag the version just installed
#
# Registered as the update-all alias by setup-01-devtools.sh.
# =============================================================================

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
sudo_keepalive

# -----------------------------------------------------------------------------
# Put the user-local tools on PATH
# -----------------------------------------------------------------------------
# The PATH entries setup-00-packages.sh and setup-01-devtools.sh write to
# .zshrc only reach an interactive zsh. Started through the update-all alias
# this script inherits them; started from anywhere else - a bash shell, cron,
# "ssh host update-all.sh" - it would not find uv, ruff, claude and herdr in
# ~/.local/bin, dotnet in ~/.dotnet, csharp-ls in ~/.dotnet/tools or nvm's npm
# at all. So the same entries are made here, as setup-01-devtools.sh makes
# them for its own run, and the telemetry opt-out it sets comes with them.
# DOTNET_ROOT is set outright, as setup-01-devtools.sh sets it, not taken from
# the environment: the install below always lands in ~/.dotnet, and the
# pruning after it must work on that same tree - an inherited DOTNET_ROOT
# pointing elsewhere would have it prune one tree and install into another.
# NVM_DIR is pinned the same way, to the directory setup-01-devtools.sh
# told the installer to use. Sourcing nvm.sh keeps whatever Node.js version
# is already active in the calling shell - an "nvm use 22" for some project,
# say - so the default is selected outright: it is the default's global
# packages that setup-01-devtools.sh installed and this script updates. No
# default means that script has not run, which is said rather than left to
# the npm step to trip over.
export PATH="$HOME/.local/bin:$PATH"
export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools"
export DOTNET_CLI_TELEMETRY_OPTOUT=1
export NVM_DIR="$HOME/.nvm"
# shellcheck disable=SC1091 # created by the nvm installer in setup-01
if [ -s "$NVM_DIR/nvm.sh" ]; then
    \. "$NVM_DIR/nvm.sh"
    if ! nvm use default > /dev/null 2>&1; then
        echo "nvm has no default Node.js version - run setup-01-devtools.sh first." >&2
        exit 1
    fi
fi

# -----------------------------------------------------------------------------
# Regenerate one Zsh completion
# -----------------------------------------------------------------------------
# The completions setup-01-devtools.sh generates - _yq, _uv, _uvx, _ruff and
# _herdr - are each produced by the tool itself, so they describe the version
# that wrote them. This script is what moves those versions, so each is
# written again right after its tool is updated, into the directory
# common.sh's ZSH_COMPLETIONS names and with the same mode
# setup-01-devtools.sh uses. Called with the completion's name and the
# command that prints it.
write_completion() {
    local name=$1
    shift
    mkdir -p "$ZSH_COMPLETIONS"
    "$@" > "$ZSH_COMPLETIONS/_$name"
    chmod 644 "$ZSH_COMPLETIONS/_$name"
    log "  Regenerated the $name Zsh completion."
}

# -----------------------------------------------------------------------------
# Pull one git clone
# -----------------------------------------------------------------------------
# The setup scripts clone a few things straight from GitHub - the Oh My Zsh
# custom plugins, Tmux Plugin Manager, the Alacritty themes - which nothing
# else updates. Each is fast-forwarded here and reported as unchanged or as
# the commit range it moved by. Called with a name for the log and the clone's
# directory; a directory that is not a clone is reported, not an error, since
# it means the setup script that makes it has not run. Always called as a
# plain statement, never under if or ||: that would switch set -e off inside
# the function, and a failed pull would then read as "up to date". A failed
# pull stops the script, as the git commands elsewhere here do.
pull_clone() {
    local name=$1 dir=$2 before after
    if [ ! -d "$dir/.git" ]; then
        log "$name is not installed - run the setup script that clones it."
        return
    fi
    before="$(git -C "$dir" rev-parse --short HEAD)"
    git -C "$dir" pull --ff-only --quiet
    after="$(git -C "$dir" rev-parse --short HEAD)"
    if [ "$before" = "$after" ]; then
        log "$name is up to date ($after)."
    else
        log "Updated $name ($before -> $after)."
    fi
}

# -----------------------------------------------------------------------------
# Update the system packages
# -----------------------------------------------------------------------------
# Done by running update-sys.sh rather than repeating what it does, so the two
# stay in step. Resolved through common.sh's SETUP_DIR, so it works no matter
# where it is called from.
step "Update the system packages"
"$SETUP_DIR/update-sys.sh"

# -----------------------------------------------------------------------------
# Update the .NET SDK
# -----------------------------------------------------------------------------
# setup-01-devtools.sh installs the SDK with dotnet-install.sh into ~/.dotnet,
# outside apt, so the same call is repeated here. It resolves the newest SDK
# of the channel and is a no-op when that version is already installed.
step "Update the .NET SDK"
DOTNET_CHANNEL="10.0"

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
# Update Node.js
# -----------------------------------------------------------------------------
# setup-01-devtools.sh installs Node.js 24 with nvm, which apt knows nothing
# about, so the same install is repeated here: "nvm install 24" resolves the
# newest 24.x and is a no-op when that is already there. A new version starts
# with an empty global package tree, so when one arrives the packages are
# carried over from the version that was the default and the default is
# moved. All of it before the npm step below, which then updates the packages
# under the new version.
#
# The default alias is set to the exact version, as setup-01-devtools.sh sets
# it, never to a floating "24": that would resolve to the newest installed
# 24.x the moment the install lands, so a carry-over that failed halfway
# would find "before" and "after" equal on the next run and never be
# retried. With the exact version, the alias moves only once the packages
# have moved. A machine set up by an earlier version of setup-01-devtools.sh
# still carries the floating alias, and its completion marker keeps that
# script from setting it again, so the alias is pinned to what it resolves
# to right here, before the install - a no-op where it is exact already.
#
# The superseded version is NOT removed. Every open terminal has its bin
# directory on PATH - nvm puts the exact version there - and deleting it
# would leave node, npm and the global tools failing in all of them until
# they are restarted. The command to remove it is printed instead.
step "Update Node.js"
log "Updating Node.js..."
NODE_BEFORE="$(nvm version default)"
nvm alias default "$NODE_BEFORE" > /dev/null
nvm install 24
NODE_AFTER="$(nvm version 24)"
if [ "$NODE_BEFORE" != "$NODE_AFTER" ]; then
    nvm reinstall-packages "$NODE_BEFORE"
    nvm alias default "$NODE_AFTER"
    nvm use default > /dev/null
    log "Node.js $NODE_BEFORE -> $NODE_AFTER; the global packages were carried over."
    log "Once the terminals that were open are restarted, remove the old version with:"
    log "  nvm uninstall $NODE_BEFORE"
fi
node -v

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
write_completion uv uv generate-shell-completion zsh
write_completion uvx uvx --generate-shell-completion zsh

# The tools uv installed, which is Ruff and whatever has been added by hand
# since - they are versioned independently of uv itself and do not move with
# it. --all rather than naming Ruff, so a tool added later is not forgotten
# here.
log "Updating the uv tools..."
uv tool upgrade --all
write_completion ruff ruff generate-shell-completion zsh

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
write_completion herdr herdr completion zsh

# -----------------------------------------------------------------------------
# Update the Oh My Zsh custom plugins
# -----------------------------------------------------------------------------
# setup-00-packages.sh clones them from GitHub. Oh My Zsh's own updater pulls
# the framework only and leaves custom/plugins alone, so they are pulled here.
step "Update the Oh My Zsh custom plugins"
for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
    pull_clone "$plugin" "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/$plugin"
done

# -----------------------------------------------------------------------------
# Update Tmux Plugin Manager and the tmux plugins
# -----------------------------------------------------------------------------
# setup-00-packages.sh clones TPM and setup-06-configs.sh has it fetch the
# plugins tmux.conf declares; apt knows neither. TPM itself is a plain clone
# and is pulled like the Zsh plugins above; update_plugins is TPM's own
# non-interactive updater for the plugins - what prefix + U does inside tmux
# - and the counterpart of the install_plugins setup-06-configs.sh runs.
step "Update Tmux Plugin Manager and the tmux plugins"
TPM_DIR="$HOME/.tmux/plugins/tpm"
pull_clone "Tmux Plugin Manager" "$TPM_DIR"
if [ -x "$TPM_DIR/bin/update_plugins" ]; then
    log "Updating the tmux plugins..."
    "$TPM_DIR/bin/update_plugins" all
fi

# -----------------------------------------------------------------------------
# Update the Alacritty themes
# -----------------------------------------------------------------------------
# setup-06-configs.sh clones the theme repository alacritty.toml imports from
# and leaves it tracking master; the path is the literal one that script
# uses, since the import in alacritty.toml names it that way.
step "Update the Alacritty themes"
pull_clone "The Alacritty themes" "$HOME/.config/alacritty/themes/alacritty-theme"

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
tmp_dir
LAZYGIT_LATEST="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest |
    grep -Po '"tag_name": *"v\K[^"]*')"
LAZYGIT_INSTALLED="$(lazygit --version | grep -Po ', version=\K[^,]*')"

if [ "$LAZYGIT_INSTALLED" = "$LAZYGIT_LATEST" ]; then
    log "lazygit $LAZYGIT_INSTALLED is up to date."
else
    log "Updating lazygit $LAZYGIT_INSTALLED -> $LAZYGIT_LATEST..."
    curl -fsSL -o "$TMP_DIR/lazygit.tar.gz" "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_LATEST}/lazygit_${LAZYGIT_LATEST}_Linux_x86_64.tar.gz"
    tar -C "$TMP_DIR" -xzf "$TMP_DIR/lazygit.tar.gz" lazygit
    sudo install -m 0755 "$TMP_DIR/lazygit" /usr/local/bin/lazygit
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
    curl -fsSL -o "$TMP_DIR/lazydocker.tar.gz" "https://github.com/jesseduffield/lazydocker/releases/download/v${LAZYDOCKER_LATEST}/lazydocker_${LAZYDOCKER_LATEST}_Linux_x86_64.tar.gz"
    tar -C "$TMP_DIR" -xzf "$TMP_DIR/lazydocker.tar.gz" lazydocker
    sudo install -m 0755 "$TMP_DIR/lazydocker" /usr/local/bin/lazydocker
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
    curl -fsSL -o "$TMP_DIR/dive.tar.gz" "https://github.com/wagoodman/dive/releases/download/v${DIVE_LATEST}/dive_${DIVE_LATEST}_linux_amd64.tar.gz"
    tar -C "$TMP_DIR" -xzf "$TMP_DIR/dive.tar.gz" dive
    sudo install -m 0755 "$TMP_DIR/dive" /usr/local/bin/dive
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
    curl -fsSL -o "$TMP_DIR/yq" "https://github.com/mikefarah/yq/releases/download/v${YQ_LATEST}/yq_linux_amd64"
    sudo install -m 0755 "$TMP_DIR/yq" /usr/local/bin/yq
    yq --version
fi
write_completion yq yq shell-completion zsh

log "Everything is up to date."
