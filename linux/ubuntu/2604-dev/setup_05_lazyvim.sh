#!/bin/bash
set -euo pipefail

# =============================================================================
# This script performs the following tasks:
# - Verifies the LazyVim prerequisites installed by setup_00_packages.sh
# - Installs the LazyVim starter into ~/.config/nvim
# - Enables the lang.json and lang.markdown LazyVim extras
# - Sets spelllang to en_us
# - Installs the plugins headlessly so the first real start is ready to go
#
# Run this AFTER setup_00_packages.sh, which installs everything LazyVim needs
# (Neovim, git, curl, unzip, ripgrep, fd, fzf, lazygit, a C compiler, python3,
# the clipboard tools and a Nerd Font). This script installs none of them - it
# only checks they are there.
#
# Everything is left at LazyVim defaults apart from the two extras and
# spelllang. The extras are a plugin SELECTION rather than configuration:
# without them the JSON and Markdown tooling is not installed at all.
#
# No lazy-lock.json is carried over, so a fresh machine resolves current
# plugin versions instead of inheriting another machine's pins.
#
# The plugins are installed at the end by running Neovim headlessly, so the
# first interactive start does not drop you into a cloning progress screen.
# =============================================================================

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
LAZYVIM_STARTER="https://github.com/LazyVim/starter"

NVIM_CONFIG="$HOME/.config/nvim"
NVIM_DATA="$HOME/.local/share/nvim"
NVIM_STATE="$HOME/.local/state/nvim"
NVIM_CACHE="$HOME/.cache/nvim"

log() {
    echo -e "\e[32m$1\e[0m"
}

# -----------------------------------------------------------------------------
# Parse the arguments
# -----------------------------------------------------------------------------
# By default an existing Neovim configuration is left completely alone. With
# --force (or FORCE=1) the four Neovim directories are moved aside to
# timestamped backups and LazyVim is installed fresh.
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

# -----------------------------------------------------------------------------
# Verify the prerequisites
# -----------------------------------------------------------------------------
# All of these come from setup_00_packages.sh. As in setup_04_alacritty.sh, this
# script installs nothing on the host - it reports what is missing and stops.
REQUIRED_COMMANDS=(
    cc
    curl
    fzf
    git
    lazygit
    nvim
    python3
    rg
    unzip
)

log "Verifying the LazyVim prerequisites..."
MISSING_COMMANDS=()
for cmd in "${REQUIRED_COMMANDS[@]}"; do
    if ! command -v "$cmd" > /dev/null 2>&1; then
        MISSING_COMMANDS+=("$cmd")
    fi
done

# Ubuntu names the fd binary fdfind; setup_00_packages.sh also links it as fd.
if ! command -v fd > /dev/null 2>&1 && ! command -v fdfind > /dev/null 2>&1; then
    MISSING_COMMANDS+=("fd")
fi

# Either clipboard tool is enough - Wayland and X11 sessions want different ones.
if ! command -v wl-copy > /dev/null 2>&1 && ! command -v xclip > /dev/null 2>&1; then
    MISSING_COMMANDS+=("wl-copy or xclip")
fi

if [ "${#MISSING_COMMANDS[@]}" -gt 0 ]; then
    echo "Missing LazyVim prerequisites: ${MISSING_COMMANDS[*]}" >&2
    echo "They are installed by setup_00_packages.sh - run that first, then" >&2
    echo "re-run this script." >&2
    exit 1
fi

# The Nerd Font is only needed for the icons, so a missing one is a warning
# rather than a reason to stop. grep reads fc-list to the end rather than
# quitting at the first match (-q): under pipefail an early quit sends fc-list
# SIGPIPE and the pipeline fails although the font is there.
if ! fc-list 2> /dev/null | grep -i "nerd font" > /dev/null; then
    log "Warning: no Nerd Font found. Icons will render as boxes."
    log "setup_00_packages.sh installs the Nerd Font symbols."
fi

nvim --version | head -1

# -----------------------------------------------------------------------------
# Move an existing configuration aside
# -----------------------------------------------------------------------------
# Only an existing configuration is a reason to stop. With --force all four
# directories are moved aside whether or not the configuration exists: LazyVim
# owns them all, and a leftover data or state directory would mix an old
# plugin state into the new configuration.
if [ -e "$NVIM_CONFIG" ] && [ "$FORCE" != "1" ]; then
    log "$NVIM_CONFIG already exists - leaving it untouched."
    log "Re-run with --force to back it up and install LazyVim fresh."
    exit 0
fi

if [ "$FORCE" = "1" ]; then
    BACKUP_SUFFIX="bak-$(date +%Y%m%d%H%M%S)"
    log "Backing up the existing Neovim directories (.$BACKUP_SUFFIX)..."
    for dir in "$NVIM_CONFIG" "$NVIM_DATA" "$NVIM_STATE" "$NVIM_CACHE"; do
        if [ -e "$dir" ]; then
            mv "$dir" "$dir.$BACKUP_SUFFIX"
            log "  $dir -> $dir.$BACKUP_SUFFIX"
        fi
    done
fi

# -----------------------------------------------------------------------------
# Install the LazyVim starter
# -----------------------------------------------------------------------------
# The .git directory is removed so the configuration becomes yours to commit
# elsewhere, which is what the LazyVim installation instructions do.
log "Cloning the LazyVim starter into $NVIM_CONFIG..."
git clone "$LAZYVIM_STARTER" "$NVIM_CONFIG"
rm -rf "$NVIM_CONFIG/.git"

# -----------------------------------------------------------------------------
# Enable the LazyVim extras
# -----------------------------------------------------------------------------
# lazyvim.json is the file :LazyExtras writes. Only the two language extras
# are enabled; everything else stays at the LazyVim default selection.
#
# The "version" field is NOT optional. LazyVim compares it against its own
# schema version and runs a migration when they differ, and the migration for
# a missing version prefixes every entry with "lazyvim.plugins.extras.". A
# file without it would therefore be rewritten to
# "lazyvim.plugins.extras.lazyvim.plugins.extras.lang.json" and the extras
# would silently not load. 8 is the current schema version; a later LazyVim
# simply migrates it forward.
log "Enabling the lang.json and lang.markdown extras..."
cat > "$NVIM_CONFIG/lazyvim.json" << 'EOF'
{
  "extras": [
    "lazyvim.plugins.extras.lang.json",
    "lazyvim.plugins.extras.lang.markdown"
  ],
  "version": 8
}
EOF

# -----------------------------------------------------------------------------
# Set spelllang to en_us
# -----------------------------------------------------------------------------
# The only option overridden here. LazyVim defaults to { "en" }, which accepts
# both US and British spellings; this narrows it to US English. Everything
# else - conceallevel, wrap, linebreak, spell, shiftwidth, tabstop - is
# already the LazyVim default and is deliberately not repeated.
log "Setting spelllang to en_us..."
cat >> "$NVIM_CONFIG/lua/config/options.lua" << 'EOF'

-- US English only (LazyVim defaults to { "en" }, which also accepts en_gb)
vim.opt.spelllang = { "en_us" }
EOF

# -----------------------------------------------------------------------------
# Install the plugins
# -----------------------------------------------------------------------------
# "Lazy! sync" is lazy.nvim's documented headless entry point: it clones,
# updates and cleans every plugin in the spec without opening a UI. Without it
# the first interactive start spends its first minute cloning ~37 plugins.
#
# What this does NOT do is install the treesitter parsers and the Mason tools.
# Those are fetched by nvim-treesitter and mason.nvim once they load, and in a
# headless sync they never load - :TSUpdateSync and :MasonInstall do not even
# exist there. They are downloaded on the first interactive start instead, and
# mason logging that it aborted an installation during this sync is expected
# and leaves nothing behind.
#
# The output is verbose and mixes in those abort notices, so it goes to a log
# and is only shown if the sync actually fails. A failure is not fatal: the
# configuration is in place and ":Lazy sync" inside Neovim does the same job.
log "Installing the plugins (this takes a minute)..."
SYNC_LOG="$(mktemp)"
if nvim --headless "+Lazy! sync" +qa > "$SYNC_LOG" 2>&1; then
    log "Plugins installed."
    rm -f "$SYNC_LOG"
else
    log "The plugin sync failed - start nvim and run :Lazy sync by hand."
    log "Output follows:"
    cat "$SYNC_LOG"
    rm -f "$SYNC_LOG"
fi

# -----------------------------------------------------------------------------
# Verify the installation
# -----------------------------------------------------------------------------
log "LazyVim installation completed successfully!"
log "Start nvim and run :checkhealth to confirm everything is in order."
