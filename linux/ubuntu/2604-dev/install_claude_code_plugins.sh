#!/bin/bash
set -euo pipefail

# =============================================================================
# This script performs the following tasks:
# - Verifies that Claude Code is installed and logged in
# - Installs the Claude Code plugins from the official marketplace
# - Adds the octanevz marketplace and installs codex-debate from it
#
# Not part of the numbered sequence: it can be run at any time after
# setup_01_devtools.sh (Claude Code, the Codex CLI and the language servers
# the plugins wrap) and after the first "claude" login. Re-running it is
# harmless - an installed plugin is reported as such and left alone.
# =============================================================================

log() {
    echo -e "\e[32m$1\e[0m"
}

# -----------------------------------------------------------------------------
# Verify Claude Code is installed and logged in
# -----------------------------------------------------------------------------
# Plugin installs talk to the marketplaces as the logged-in account, and the
# CLI would otherwise stop to ask for a login mid-run. "claude auth status"
# prints JSON with a loggedIn field; it is grepped rather than parsed so this
# script needs nothing beyond what setup_00 installs.
if ! command -v claude > /dev/null 2>&1; then
    echo "Claude Code is not installed - run setup_01_devtools.sh first." >&2
    exit 1
fi

if ! claude auth status 2> /dev/null | grep -q '"loggedIn": *true'; then
    echo "Claude Code is not logged in. Run 'claude' once and sign in, or" >&2
    echo "'claude auth login', then re-run this script." >&2
    exit 1
fi
log "Claude Code is logged in."

# -----------------------------------------------------------------------------
# Install Claude Code Plugins (official marketplace)
# -----------------------------------------------------------------------------
# The three *-lsp plugins only wrap a language server: csharp-ls, pyright and
# typescript-language-server, all installed by setup_01_devtools.sh.
claude plugin install claude-code-setup@claude-plugins-official
claude plugin install code-simplifier@claude-plugins-official
claude plugin install commit-commands@claude-plugins-official
claude plugin install context7@claude-plugins-official
claude plugin install csharp-lsp@claude-plugins-official
claude plugin install feature-dev@claude-plugins-official
claude plugin install frontend-design@claude-plugins-official
claude plugin install hookify@claude-plugins-official
claude plugin install playground@claude-plugins-official
claude plugin install pyright-lsp@claude-plugins-official
claude plugin install security-guidance@claude-plugins-official
claude plugin install skill-creator@claude-plugins-official
claude plugin install typescript-lsp@claude-plugins-official

# -----------------------------------------------------------------------------
# Install Claude Code Plugins (own marketplace)
# -----------------------------------------------------------------------------
# codex-debate drives the Codex CLI, which setup_01_devtools.sh installs via
# npm install -g @openai/codex - so run this script after setup_01_devtools.sh.
claude plugin marketplace add octanevz/codex-debate
claude plugin install codex-debate@octanevz

log "Claude Code plugins installed successfully!"
