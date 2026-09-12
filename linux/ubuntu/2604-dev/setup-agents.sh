#!/bin/bash
set -euo pipefail

# =============================================================================
# This script performs the following tasks:
# - Verifies that Claude Code and the Codex CLI are installed and logged in
# - Installs the Claude Code plugins from the official marketplace
# - Adds the octanevz marketplace and installs codex-debate from it
# - Installs agent skills for Claude Code, Codex and OpenCode at once
#
# Not part of the numbered sequence: it can be run at any time after
# setup-01-devtools.sh (Claude Code, the Codex CLI and the language servers
# the plugins wrap) and after the first "claude" and "codex" logins.
# Re-running it is harmless - an installed plugin is reported as such and
# left alone.
# =============================================================================

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

step "Verify the agents are installed and logged in"

# -----------------------------------------------------------------------------
# Verify Claude Code is installed and logged in
# -----------------------------------------------------------------------------
# Plugin installs talk to the marketplaces as the logged-in account, and the
# CLI would otherwise stop to ask for a login mid-run. "claude auth status"
# prints JSON with a loggedIn field; one field is all that is needed, so it is
# grepped rather than run through jq.
log "Verifying Claude Code is installed and logged in..."
if ! command -v claude > /dev/null 2>&1; then
    echo "Claude Code is not installed - run setup-01-devtools.sh first." >&2
    exit 1
fi

if ! claude auth status 2> /dev/null | grep -q '"loggedIn": *true'; then
    echo "Claude Code is not logged in. Run 'claude' once and sign in, or" >&2
    echo "'claude auth login', then re-run this script." >&2
    exit 1
fi
log "Claude Code is logged in."

# -----------------------------------------------------------------------------
# Verify the Codex CLI is installed and logged in
# -----------------------------------------------------------------------------
# codex-debate drives the Codex CLI, and the skills below are installed for
# Codex too, so a missing login is caught here rather than on the first
# debate. "codex login status" exits 0 when logged in and 1 otherwise.
log "Verifying the Codex CLI is installed and logged in..."
if ! command -v codex > /dev/null 2>&1; then
    echo "The Codex CLI is not installed - run setup-01-devtools.sh first." >&2
    exit 1
fi

if ! codex login status > /dev/null 2>&1; then
    echo "The Codex CLI is not logged in. Run 'codex login' and sign in, then" >&2
    echo "re-run this script." >&2
    exit 1
fi
log "The Codex CLI is logged in."

# -----------------------------------------------------------------------------
# Install Claude Code Plugins (official marketplace)
# -----------------------------------------------------------------------------
# The three *-lsp plugins only wrap a language server: csharp-ls, pyright and
# typescript-language-server, all installed by setup-01-devtools.sh.
step "Install the Claude Code plugins"
log "Installing the plugins from the official marketplace..."
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
# codex-debate drives the Codex CLI, which setup-01-devtools.sh installs via
# npm install -g @openai/codex - so run this script after setup-01-devtools.sh.
log "Installing the plugins from the own marketplace..."
claude plugin marketplace add octanevz/codex-debate
claude plugin install codex-debate@octanevz

# -----------------------------------------------------------------------------
# Install agent skills for Claude Code, Codex and OpenCode
# -----------------------------------------------------------------------------
# Skills are shared between the agents, so they are installed once with the
# skills CLI (https://skills.sh) rather than per agent: it puts them under
# ~/.agents/skills, which Codex and OpenCode read directly, and symlinks them
# into ~/.claude/skills for Claude Code. Run through npx so nothing has to be
# installed or updated - update-all.sh runs "skills update" the same way.
#
# Each entry is a GitHub repository followed by the skills to take from it.
# The Orca ones are the three Orca ADE itself installs on first launch;
# find-skills is the skills CLI's own discovery skill. -a and -s are
# repeated per value - the CLI does not split comma-separated lists.
step "Install the agent skills"
log "Installing the skills for Claude Code, Codex and OpenCode..."
SKILL_AGENTS=(claude-code codex opencode)
SKILL_SOURCES=(
    "stablyai/orca computer-use orca-cli orchestration"
    "vercel-labs/skills find-skills"
)

AGENT_ARGS=()
for agent in "${SKILL_AGENTS[@]}"; do
    AGENT_ARGS+=(-a "$agent")
done

for source in "${SKILL_SOURCES[@]}"; do
    read -r repo skills <<< "$source"
    SKILL_ARGS=()
    for skill in $skills; do
        SKILL_ARGS+=(-s "$skill")
    done
    log "Installing $skills from $repo for ${SKILL_AGENTS[*]}..."
    npx -y skills add "$repo" -g -y "${AGENT_ARGS[@]}" "${SKILL_ARGS[@]}"
done

log "Claude Code plugins and agent skills installed successfully!"
