#!/bin/bash
set -e;

# =========================================================================
# This script performs the following tasks:
# - Updates the OS and installs required packages
# - Installs Oh My Zsh with autosuggestions and syntax highlighting plugins
# - Sets Zsh as the default shell
# - Optionally reboots the system after installation
# =========================================================================

# --------------------------------------------
# Update OS and install some required packages
# --------------------------------------------
sudo apt update -y \
    && sudo apt upgrade -y \
    && sudo apt install -y \
        apt-transport-https \
        btop \
        ca-certificates \
        curl \
        fastfetch \
        gimp \
        git \
        gnome-keyring \
        gnome-shell-extension-manager \
        gnome-shell-extensions \
        gnome-tweaks \
        gnupg \
        gnupg2 \
        gpg \
        libc6 \
        libfontconfig1 \
        libfuse2 \
        libgcc-s1 \
        libicu-dev \
        libicu76 \
        liblttng-ust1 \
        libsecret-1-0 \
        libsecret-1-dev \
        libssl3 \
        libstdc++6 \
        lsb-release \
        mesa-utils \
        open-vm-tools-desktop \
        unzip \
        uuid-runtime \
        wget \
        zlib1g \
        zsh \
        zsh-autosuggestions \
        zsh-syntax-highlighting \
    && sudo apt autoremove -y \
    && sudo apt clean -y;

# -----------------------------
# Install Oh My Zsh and plugins
# -----------------------------

log() {
    echo -e "\e[32m$1\e[0m";
}

# Install Oh My Zsh if not already installed
if [ -d "$HOME/.oh-my-zsh" ]; then
    log "Oh My Zsh is already installed at $HOME/.oh-my-zsh. Skipping installation.";
else
    log "Installing Oh My Zsh...";
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended;
fi

# Set Zsh as the default shell
log "Setting Zsh as the default shell...";
chsh -s $(which zsh);

# Install Zsh autosuggestions
if [ ! -d "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ]; then
    log "Installing Zsh autosuggestions...";
    git clone https://github.com/zsh-users/zsh-autosuggestions $HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions;
else
    log "Zsh autosuggestions already installed. Skipping.";
fi

# Install Zsh syntax highlighting
if [ ! -d "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" ]; then
    log "Installing Zsh syntax highlighting...";
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting;
else
    log "Zsh syntax highlighting already installed. Skipping.";
fi

# Update .zshrc to enable plugins
log "Configuring Zsh plugins in .zshrc...";
if ! grep -q "zsh-autosuggestions" ~/.zshrc; then
    sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' ~/.zshrc;
    log "Updated plugins in .zshrc.";
else
    log "Plugins already configured in .zshrc.";
fi

log "Oh My Zsh installation completed with autosuggestions and syntax highlighting enabled!";

# -------------------------
# Reboot after installation
# -------------------------
read -r -p "Reboot? (j/N): " reply;
if [[ "$reply" =~ ^[JjYy]$ ]]; then
    echo "Rebooting...";
    exec sudo /sbin/reboot now;
fi
