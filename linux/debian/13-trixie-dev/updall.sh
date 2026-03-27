#!/bin/bash
set -e;

# =========================================================================
# This script performs the following tasks:
# - Updates and upgrades Debian packages
# - Removes unused packages and cleans up the local repository
# - Updates all global npm packages
# - Updates Claude Code
# =========================================================================

# Update and clean up Debian packages
sudo apt update -y \
    && sudo apt upgrade -y \
    && sudo apt autoremove -y \
    && sudo apt autoclean -y;

# Update global npm packages
npm update -g;

# Update Claude Code
claude update;
