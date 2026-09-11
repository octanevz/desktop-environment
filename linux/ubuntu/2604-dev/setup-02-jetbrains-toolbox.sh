#!/bin/bash
set -euo pipefail

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
setup_begin "$@"

# Nothing between here and the end leaves the machine untouched - it runs the Toolbox installer
# straight away - so the completion marker goes now.
setup_invalidate

# Install JetBrains Toolbox. CI=1 stops the installer from launching Toolbox
# itself: it does so with a bare "&", leaving the app attached to the
# terminal, so its output lands on the prompt and, worse, whatever captures
# this script's output (a pipe, tee, a log) waits until Toolbox exits. The
# launch happens below instead, detached.
curl -fsSL https://raw.githubusercontent.com/nagygergo/jetbrains-toolbox-install/4184247d1d12888024181f27dea7b7868d8f9e81/jetbrains-toolbox.sh | CI=1 bash

# The first launch is what writes the .desktop file (setup-07-configs.sh pins
# it to the dock) and the autostart entry, so it has to happen. setsid puts
# Toolbox in its own session, -f forks so this script does not wait, and the
# redirections cut it off the terminal - nothing is left to press Enter for.
log "Launching JetBrains Toolbox for its first-time setup..."
setsid -f "$HOME/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox" \
    < /dev/null > /dev/null 2>&1

setup_end
