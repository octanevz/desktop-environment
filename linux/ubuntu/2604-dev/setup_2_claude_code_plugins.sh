#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Install Claude Code Plugins (official marketplace)
# -----------------------------------------------------------------------------
# The three *-lsp plugins only wrap a language server: csharp-ls, pyright and
# typescript-language-server, all installed by setup_1_devtools.sh.
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
# codex-debate drives the Codex CLI, which setup_1_devtools.sh installs via
# npm install -g @openai/codex - so run this script after setup_1_devtools.sh.
claude plugin marketplace add octanevz/codex-debate
claude plugin install codex-debate@octanevz
