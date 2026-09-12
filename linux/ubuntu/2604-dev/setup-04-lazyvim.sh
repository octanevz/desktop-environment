#!/bin/bash
set -euo pipefail

# =============================================================================
# This script performs the following tasks:
# - Verifies Neovim and the LazyVim prerequisites installed by
#   setup-00-packages.sh and setup-01-devtools.sh
# - Installs the LazyVim starter into ~/.config/nvim
# - Enables the lang.json and lang.markdown LazyVim extras plus the
#   recommended ai.copilot, coding.yanky, editor.dial, editor.inc-rename,
#   editor.snacks_explorer, editor.snacks_picker, test.core, util.dot and
#   util.mini-hipatterns extras
# - Sets spelllang to en_us
# - Sets a longer git timeout and a lower headless concurrency in lazy.nvim,
#   so the sync completes on a slow link instead of failing plugin by plugin
# - Installs the plugins headlessly so the first real start is ready to go
#
# Run this AFTER setup-00-packages.sh, which installs the LazyVim
# prerequisites (git, curl, unzip, ripgrep, fd, fzf, a C compiler, python3,
# the clipboard tools and a Nerd Font), and setup-01-devtools.sh, which
# installs Neovim itself, lazygit for LazyVim's lazygit integration and
# Node.js for the Copilot language server; this script verifies they are
# there.
#
# Everything is left at LazyVim defaults apart from the extras and spelllang.
# The extras are a plugin SELECTION rather than configuration: without them
# the JSON and Markdown tooling, Copilot and the rest are not installed at
# all.
#
# Copilot still has to be signed in once by hand: start nvim and run
# :Copilot auth, which shows a device code to enter on GitHub.
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

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

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

setup_begin "$@"

# -----------------------------------------------------------------------------
# Verify the prerequisites
# -----------------------------------------------------------------------------
# All of these come from setup-00-packages.sh except nvim, lazygit and node,
# which setup-01-devtools.sh installs (node is needed by the Copilot language
# server). As in setup-03-alacritty.sh, the script reports what is missing
# and stops.
step "Verify the prerequisites"
REQUIRED_COMMANDS=(
    cc
    curl
    fzf
    git
    lazygit
    node
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

# Ubuntu names the fd binary fdfind; setup-00-packages.sh also links it as fd.
if ! command -v fd > /dev/null 2>&1 && ! command -v fdfind > /dev/null 2>&1; then
    MISSING_COMMANDS+=("fd")
fi

# Either clipboard tool is enough - Wayland and X11 sessions want different ones.
if ! command -v wl-copy > /dev/null 2>&1 && ! command -v xclip > /dev/null 2>&1; then
    MISSING_COMMANDS+=("wl-copy or xclip")
fi

if [ "${#MISSING_COMMANDS[@]}" -gt 0 ]; then
    echo "Missing LazyVim prerequisites: ${MISSING_COMMANDS[*]}" >&2
    echo "They are installed by setup-00-packages.sh (nvim, lazygit and node" >&2
    echo "by setup-01-devtools.sh) - run those first, then re-run this" >&2
    echo "script." >&2
    exit 1
fi

# The Nerd Font is only needed for the icons, so a missing one is a warning
# rather than a reason to stop. grep reads fc-list to the end rather than
# quitting at the first match (-q): under pipefail an early quit sends fc-list
# SIGPIPE and the pipeline fails although the font is there.
if ! fc-list 2> /dev/null | grep -i "nerd font" > /dev/null; then
    log "Warning: no Nerd Font found. Icons will render as boxes."
    log "setup-00-packages.sh installs the Nerd Font symbols."
fi

nvim --version | head -1

# -----------------------------------------------------------------------------
# Move an existing configuration aside
# -----------------------------------------------------------------------------
# Only an existing configuration is a reason to stop. With --force all four
# directories are moved aside whether or not the configuration exists: LazyVim
# owns them all, and a leftover data or state directory would mix an old
# plugin state into the new configuration.
step "Move an existing configuration aside"
if [ -e "$NVIM_CONFIG" ] && [ "$FORCE" != "1" ]; then
    log "$NVIM_CONFIG already exists - leaving it untouched."
    log "Re-run with --force to back it up and install LazyVim fresh."
    exit 0
fi

# Below the exit 0 for an existing configuration; the backup move just
# below is the first thing that touches the machine.
setup_invalidate

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
step "Install the LazyVim starter"
log "Cloning the LazyVim starter into $NVIM_CONFIG..."
git clone "$LAZYVIM_STARTER" "$NVIM_CONFIG"
rm -rf "$NVIM_CONFIG/.git"

# -----------------------------------------------------------------------------
# Enable the LazyVim extras
# -----------------------------------------------------------------------------
# lazyvim.json is the file :LazyExtras writes. The two language extras are
# enabled together with the extras :LazyExtras marks as recommended:
#
#   ai.copilot             GitHub Copilot suggestions (needs :Copilot auth)
#   coding.yanky           yank history with a picker and put cycling
#   editor.dial            <C-a>/<C-x> on dates, booleans, semver and more
#   editor.inc-rename      incremental LSP rename with a live preview
#   editor.snacks_explorer the snacks.nvim file explorer
#   editor.snacks_picker   the snacks.nvim picker for files, grep and more
#   test.core              neotest and its keymaps under <leader>t
#   util.dot               dotfile support (bash, zsh, tmux, ... treesitter)
#   util.mini-hipatterns   highlights color codes like #ff0000 in their color
#
# snacks_explorer and snacks_picker are what LazyVim picks by default when no
# other explorer or picker extra is enabled; listing them pins that choice.
# Everything else stays at the LazyVim default selection.
#
# The "version" field is NOT optional. LazyVim compares it against its own
# schema version and runs a migration when they differ, and the migration for
# a missing version prefixes every entry with "lazyvim.plugins.extras.". A
# file without it would therefore be rewritten to
# "lazyvim.plugins.extras.lazyvim.plugins.extras.lang.json" and the extras
# would silently not load. 8 is the current schema version; a later LazyVim
# simply migrates it forward.
step "Enable the LazyVim extras"
log "Enabling the LazyVim extras..."
cat > "$NVIM_CONFIG/lazyvim.json" << 'EOF'
{
  "extras": [
    "lazyvim.plugins.extras.ai.copilot",
    "lazyvim.plugins.extras.coding.yanky",
    "lazyvim.plugins.extras.editor.dial",
    "lazyvim.plugins.extras.editor.inc-rename",
    "lazyvim.plugins.extras.editor.snacks_explorer",
    "lazyvim.plugins.extras.editor.snacks_picker",
    "lazyvim.plugins.extras.lang.json",
    "lazyvim.plugins.extras.lang.markdown",
    "lazyvim.plugins.extras.test.core",
    "lazyvim.plugins.extras.util.dot",
    "lazyvim.plugins.extras.util.mini-hipatterns"
  ],
  "version": 8
}
EOF

# -----------------------------------------------------------------------------
# Set spelllang to en_us
# -----------------------------------------------------------------------------
# The only option overridden here. LazyVim defaults to { "en" }, which accepts
# both US and British spellings; this narrows it to US English.
step "Set spelllang to en_us"
log "Setting spelllang to en_us..."
cat >> "$NVIM_CONFIG/lua/config/options.lua" << 'EOF'

-- US English only (LazyVim defaults to { "en" }, which also accepts en_gb)
vim.opt.spelllang = { "en_us" }
EOF

# -----------------------------------------------------------------------------
# Make lazy.nvim tolerate a slow link
# -----------------------------------------------------------------------------
# The plugin sync below is ~40 git clones from GitHub. lazy.nvim runs them all
# at once and kills any git process after two minutes, which on a slow link
# (a few KiB/s per clone was seen in a VM) means the larger plugins never
# finish and the sync reports them as failed. Two settings are added to the
# starter's lazy.nvim options: git.timeout goes up to fifteen minutes, and
# when Neovim is headless - this script's sync - at most four clones run at
# once, so each gets enough of the link to finish. Interactive use keeps
# lazy.nvim's default concurrency; the longer timeout only ever matters when
# something is slow.
#
# The lines go in after the "install = { colorscheme ..." option, which is
# checked for first so a changed starter fails loudly rather than silently
# skipping this.
step "Make lazy.nvim tolerate a slow link"
LAZY_LUA="$NVIM_CONFIG/lua/config/lazy.lua"
if ! grep -q '^  install = { colorscheme = ' "$LAZY_LUA"; then
    echo "The starter's $LAZY_LUA has changed shape - the install = { colorscheme" >&2
    echo "line is missing, so the slow-link settings cannot be inserted." >&2
    exit 1
fi
log "Setting the git timeout and the headless concurrency in lazy.lua..."
sed -i '/^  install = { colorscheme = /a\
  -- A slow link: give each git process fifteen minutes rather than the\
  -- default two, and when headless (the sync in setup-04-lazyvim.sh) run at\
  -- most four clones at once, so each gets enough of the link to finish.\
  git = { timeout = 900 },\
  concurrency = #vim.api.nvim_list_uis() == 0 and 4 or nil,' "$LAZY_LUA"
log "  Done."

# -----------------------------------------------------------------------------
# Install the plugins
# -----------------------------------------------------------------------------
# "Lazy! sync" is lazy.nvim's documented headless entry point: it clones,
# updates and cleans every plugin in the spec without opening a UI. Without it
# the first interactive start spends its first minute cloning ~37 plugins.
#
# A clone that still hits the timeout above is retried once with
# "Lazy! install", which only touches plugins that are not installed - on a
# good link that pass returns at once. What is still missing after that is
# listed by name, from lazy.nvim's own plugin state.
#
# The treesitter parsers and the Mason tools are downloaded on the first
# interactive start instead: nvim-treesitter and mason.nvim fetch them once
# they load, and in a headless sync they never load. mason logging that it
# aborted an installation during this sync is expected and leaves nothing
# behind. The same goes for copilot.lua's build step (:Copilot auth): it
# cannot complete without you, so it is repeated by hand on the first start.
#
# The output is verbose and mixes in those abort notices, so it goes to a log
# and is only shown if the sync actually fails. A failure is not fatal: the
# configuration is in place and ":Lazy sync" inside Neovim does the same job.
step "Install the plugins"
log "Installing the plugins (this takes a minute on a good link)..."
SYNC_LOG="$(mktemp)"
if nvim --headless "+Lazy! sync" +qa > "$SYNC_LOG" 2>&1; then
    log "Plugin sync finished."
    rm -f "$SYNC_LOG"
else
    log "The plugin sync failed - start nvim and run :Lazy sync by hand."
    log "Output follows:"
    cat "$SYNC_LOG"
    rm -f "$SYNC_LOG"
fi

log "Retrying any plugin the sync left uninstalled..."
nvim --headless "+Lazy! install" +qa > /dev/null 2>&1 || true

# lazy.nvim's own view of each plugin: _.installed is what :Lazy shows as
# installed. Printed to stderr so that Neovim's own messages, which go to
# stdout when headless, stay out of the list.
MISSING_PLUGINS="$(nvim --headless -c 'lua for _, p in pairs(require("lazy.core.config").plugins) do if not p._.installed then io.stderr:write(p.name .. "\n") end end' +qa 2>&1 > /dev/null || true)"
if [ -z "$MISSING_PLUGINS" ]; then
    log "Plugins installed."
else
    log "Still not installed - start nvim and run :Lazy sync to finish:"
    while IFS= read -r name; do
        log "  $name"
    done <<< "$MISSING_PLUGINS"
fi

# -----------------------------------------------------------------------------
# Verify the installation
# -----------------------------------------------------------------------------
step "Verify the installation"
log "LazyVim installation completed successfully!"
log "Start nvim and run :checkhealth to confirm everything is in order,"
log "then :Copilot auth to sign in to GitHub Copilot."

setup_end
