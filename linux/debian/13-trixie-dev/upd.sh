#!/bin/bash
set -e;

# =========================================================================
# This script performs the following tasks:
# - Updates and upgrades Debian packages
# - Removes unused packages and cleans up the local repository
# =========================================================================

# Update and clean up Debian packages
sudo apt update -y \
    && sudo apt upgrade -y \
    && sudo apt autoremove -y \
    && sudo apt autoclean -y;
