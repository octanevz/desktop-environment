#!/bin/bash
set -euo pipefail

# =============================================================================
# This script performs the following tasks:
# - Updates and cleans up the Ubuntu packages
# - Refreshes the snaps
#
# Registered as the update-sys alias by setup-01-devtools.sh, and run first by
# update-all.sh.
# =============================================================================

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
sudo_keepalive

# -----------------------------------------------------------------------------
# Update the Ubuntu packages
# -----------------------------------------------------------------------------
# One statement per line: set -e ignores a failure anywhere but the last link
# of an && chain, so a chain would exit 0 after a failed upgrade and
# update-all.sh could not tell.
step "Update the Ubuntu packages"
sudo apt update -y
sudo apt upgrade -y
sudo apt autoremove -y
sudo apt autoclean -y

# -----------------------------------------------------------------------------
# Refresh the snaps
# -----------------------------------------------------------------------------
# Ubuntu ships parts of the desktop as snaps.
step "Refresh the snaps"
if command -v snap > /dev/null 2>&1; then
    sudo snap refresh
fi
