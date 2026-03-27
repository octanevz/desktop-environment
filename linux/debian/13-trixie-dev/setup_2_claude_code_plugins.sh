#!/bin/bash
set -e;

# ---------------------------
# Install Claude Code Plugins
# ---------------------------
echo "Installing Claude Code Plugins...";

claude plugin install claude-code-setup@claude-plugins-official;
claude plugin install code-simplifier@claude-plugins-official;
claude plugin install commit-commands@claude-plugins-official;
claude plugin install context7@claude-plugins-official;
claude plugin install csharp-lsp@claude-plugins-official;
claude plugin install feature-dev@claude-plugins-official;
claude plugin install frontend-design@claude-plugins-official;
claude plugin install hookify@claude-plugins-official;
claude plugin install playground@claude-plugins-official;
claude plugin install pyright-lsp@claude-plugins-official;
claude plugin install security-guidance@claude-plugins-official;
claude plugin install skill-creator@claude-plugins-official;
claude plugin install superpowers@claude-plugins-official;
claude plugin install typescript-lsp@claude-plugins-official;

echo "Claude Code Plugin installation completed successfully!";
