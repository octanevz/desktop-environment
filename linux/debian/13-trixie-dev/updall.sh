#!/bin/bash
set -e;

# Update and clean up Debian packages
sudo apt update -y \
    && sudo apt upgrade -y \
    && sudo apt autoremove -y \
    && sudo apt autoclean -y;

# Update global npm packages
npm update -g;

# Update Claude Code
claude update;
