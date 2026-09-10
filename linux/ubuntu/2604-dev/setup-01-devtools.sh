#!/bin/bash
set -euo pipefail

# =============================================================================
# This script performs the following tasks:
# - Installs Docker Engine and Containerd
# - Installs Neovim
# - Installs lazygit and lazydocker
# - Installs Google Chrome
# - Installs Visual Studio Code
# - Installs Orca ADE
# - Installs GitHub CLI
# - Installs Node.js 24 using nvm
# - Installs npm packages (Codex CLI, OpenCode, markdown-tree-parser,
#   Prettier, markdownlint-cli2, the Pyright and TypeScript language
#   servers)
# - Installs .NET 10 LTS with Microsoft's dotnet-install.sh and the csharp-ls
#   language server
# - Installs Claude Code
# - Installs herdr and its Zsh completion
# - Registers update-sys and update-all aliases in .zshrc
# =============================================================================

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
setup_begin "$@"

# Downloads an apt signing key into /etc/apt/keyrings. apt accepts armored
# (.asc) and binary (.gpg) keys alike in Signed-By, so nothing is dearmored.
# The download is staged in a temp file and only installed once it succeeded,
# so a failed download can never truncate a keyring that is already in use.
install_keyring() {
    local url=$1 name=$2 tmp
    tmp="$(mktemp)"
    curl -fsSL -o "$tmp" "$url"
    sudo install -D -o root -g root -m 644 "$tmp" "/etc/apt/keyrings/$name"
    rm -f "$tmp"
}

# -----------------------------------------------------------------------------
# Install Docker Engine and Containerd
# -----------------------------------------------------------------------------

# uninstall all conflicting packages
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt remove -y $pkg || true; done

# Add Docker's official GPG key:
install_keyring https://download.docker.com/linux/ubuntu/gpg docker.asc

# Add the repository to Apt sources:
# UBUNTU_CODENAME is used rather than VERSION_CODENAME so the correct suite is
# picked on Ubuntu derivatives too. Docker publishes per-Ubuntu-release suites;
# if the repo does not carry this release yet, pin the previous LTS codename here.
# shellcheck disable=SC1091 # /etc/os-release is read on the target machine
sudo tee /etc/apt/sources.list.d/docker.sources << EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "$UBUNTU_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update -y

# Install latest version of Docker Engine and containerd
sudo apt -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Post-installation steps: manage Docker as a non-root user
sudo groupadd docker || true
sudo usermod -aG docker "$USER"

# -----------------------------------------------------------------------------
# Install Neovim
# -----------------------------------------------------------------------------
# The Ubuntu archive freezes Neovim at the version available at release time,
# which goes stale long before the next LTS, so the official upstream
# "stable" tarball is installed to /opt instead of the apt package. Re-run
# this script to move it to a newer stable; update-all.sh leaves it alone so
# that a Neovim bump cannot break the LazyVim plugins unannounced.
log "Installing Neovim (stable) from the official tarball..."

NVIM_TARBALL="nvim-linux-x86_64.tar.gz"
NVIM_PREFIX="/opt/nvim-linux-x86_64"

curl -fsSL -o "/tmp/$NVIM_TARBALL" "https://github.com/neovim/neovim/releases/download/stable/$NVIM_TARBALL"
sudo rm -rf "$NVIM_PREFIX"
sudo tar -C /opt -xzf "/tmp/$NVIM_TARBALL"
rm -f "/tmp/$NVIM_TARBALL"

if ! grep -q "$NVIM_PREFIX/bin" ~/.zshrc; then
    echo "export PATH=\"\$PATH:$NVIM_PREFIX/bin\"" >> ~/.zshrc
    log "Added Neovim to PATH in .zshrc."
else
    log "Neovim already on PATH in .zshrc."
fi
export PATH="$PATH:$NVIM_PREFIX/bin"

nvim --version | head -1

# -----------------------------------------------------------------------------
# Install lazygit
# -----------------------------------------------------------------------------
# Installed from its GitHub releases rather than the archive, whose version
# is pinned for the lifetime of the release. update-all.sh refreshes it.
log "Installing lazygit..."

LAZYGIT_VERSION="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | grep -Po '"tag_name": *"v\K[^"]*')"
curl -fsSL -o /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${LAZYGIT_VERSION}/lazygit_${LAZYGIT_VERSION}_Linux_x86_64.tar.gz"
tar -C /tmp -xzf /tmp/lazygit.tar.gz lazygit
sudo install -m 0755 /tmp/lazygit /usr/local/bin/lazygit
rm -f /tmp/lazygit.tar.gz /tmp/lazygit

lazygit --version

# -----------------------------------------------------------------------------
# Install lazydocker
# -----------------------------------------------------------------------------
# A terminal UI for Docker from the lazygit author, installed the same way:
# from its GitHub releases, since Ubuntu does not package it. update-all.sh
# refreshes it.
log "Installing lazydocker..."

LAZYDOCKER_VERSION="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazydocker/releases/latest | grep -Po '"tag_name": *"v\K[^"]*')"
curl -fsSL -o /tmp/lazydocker.tar.gz "https://github.com/jesseduffield/lazydocker/releases/download/v${LAZYDOCKER_VERSION}/lazydocker_${LAZYDOCKER_VERSION}_Linux_x86_64.tar.gz"
tar -C /tmp -xzf /tmp/lazydocker.tar.gz lazydocker
sudo install -m 0755 /tmp/lazydocker /usr/local/bin/lazydocker
rm -f /tmp/lazydocker.tar.gz /tmp/lazydocker

lazydocker --version | head -1

# -----------------------------------------------------------------------------
# Install Google Chrome
# -----------------------------------------------------------------------------

# Add Google signing key and repository
log "Installing the Google signing key and repository..."
install_keyring https://dl.google.com/linux/linux_signing_key.pub google-chrome.asc

sudo tee /etc/apt/sources.list.d/google-chrome.sources << EOF
Types: deb
URIs: http://dl.google.com/linux/chrome/deb/
Suites: stable
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/google-chrome.asc
EOF

sudo apt update -y

log "Installing Google Chrome (stable)..."
sudo apt install -y google-chrome-stable

# Remove the .list file auto-created by Chrome's post-install script (duplicate of .sources)
sudo rm -f /etc/apt/sources.list.d/google-chrome.list

# Verify installation
log "Google Chrome installation completed successfully!"
google-chrome --version

# -----------------------------------------------------------------------------
# Install Visual Studio Code
# -----------------------------------------------------------------------------
# Installed from the Microsoft apt repository rather than the snap, so that
# update-sys/update-all keep it current together with everything else.

# Import the Microsoft GPG key
install_keyring https://packages.microsoft.com/keys/microsoft.asc microsoft.asc

# Add the VS Code repository to the sources list
sudo tee /etc/apt/sources.list.d/vscode.sources << EOF
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /etc/apt/keyrings/microsoft.asc
EOF

# Update package lists and install VS Code
sudo apt update -y
sudo apt install -y code

# -----------------------------------------------------------------------------
# Install Orca ADE
# -----------------------------------------------------------------------------
# Orca ADE ships as a .deb attached to its GitHub releases, not from an apt
# repository, and its CLI has no update command, so update-all does not touch
# it. It does not need to: the app self-updates through electron-updater from
# the same GitHub releases (Check for Updates / Restart to Update), installing
# the new .deb with dpkg. This section only seeds the initial install - and,
# because a self-update goes through dpkg too, the version check below sees
# whatever the app updated itself to.
#
# The releases carry no stable "latest" download URL either, so the newest
# amd64 .deb is resolved through the GitHub API.
#
# Dependencies are left to apt (the .deb is installed by path, not with dpkg).
# Verified against Ubuntu 26.04 (resolute): the package's libgtk-3-0 and
# libatspi2.0-0 dependencies no longer exist under those names, but
# libgtk-3-0t64 and libatspi2.0-0t64 Provide them, so apt resolves both. The
# rest it pulls in - libayatana-appindicator3-1, libayatana-ido3-0.4-0,
# libayatana-indicator3-7, libxdo3, xdotool, xvfb, xclip - are all present,
# some from universe, which setup-00-packages.sh enables.
log "Installing Orca ADE..."

ORCA_ASSET_URL="$(curl -fsSL https://api.github.com/repos/stablyai/orca/releases/latest |
    grep -Po '"browser_download_url": *"\K[^"]+/orca-ide_[^"/]+_amd64\.deb(?=")' |
    head -1)"

if [ -z "$ORCA_ASSET_URL" ]; then
    echo "No orca-ide_*_amd64.deb asset found in the latest stablyai/orca release." >&2
    exit 1
fi

ORCA_DEB="${ORCA_ASSET_URL##*/}"
ORCA_VERSION="${ORCA_DEB#orca-ide_}"
ORCA_VERSION="${ORCA_VERSION%_amd64.deb}"

# Skip the ~164 MB download when the installed version is already the latest.
if dpkg-query -W -f='${Version}' orca-ide 2> /dev/null | grep -qx "$ORCA_VERSION"; then
    log "Orca ADE $ORCA_VERSION is already installed. Skipping."
else
    log "Installing Orca ADE $ORCA_VERSION..."
    curl -fsSL -o "/tmp/$ORCA_DEB" "$ORCA_ASSET_URL"
    # Installed by path so apt pulls in the dependencies itself.
    sudo apt install -y "/tmp/$ORCA_DEB"
    rm -f "/tmp/$ORCA_DEB"
fi

# The package installs to /opt/Orca and puts its CLI at
# /opt/Orca/resources/bin/orca-ide. Link it into ~/.local/bin, which
# setup-00-packages.sh puts on PATH.
#
# The CLI is called orca-ide, never plain orca, and it must stay that way:
# "orca" is the GNOME screen reader package on Debian/Ubuntu and owns
# /usr/bin/orca, so a bare "orca" symlink would start speech output.
mkdir -p "$HOME/.local/bin"
ln -sfn /opt/Orca/resources/bin/orca-ide "$HOME/.local/bin/orca-ide"
log "Linked orca-ide into ~/.local/bin."

dpkg-query -W -f='Orca ADE ${Version} installed successfully!\n' orca-ide

# -----------------------------------------------------------------------------
# Install GitHub CLI
# -----------------------------------------------------------------------------
# The Ubuntu archive version is frozen per release, so the upstream repo is used.

log "Installing the GitHub CLI signing key and repository..."
install_keyring https://cli.github.com/packages/githubcli-archive-keyring.gpg githubcli-archive-keyring.gpg

sudo tee /etc/apt/sources.list.d/github-cli.sources << EOF
Types: deb
URIs: https://cli.github.com/packages
Suites: stable
Components: main
Architectures: amd64
Signed-By: /etc/apt/keyrings/githubcli-archive-keyring.gpg
EOF

sudo apt update -y
sudo apt install -y gh

gh --version

# -----------------------------------------------------------------------------
# Install Node.js 24 using nvm
# -----------------------------------------------------------------------------
log "Installing Node.js..."

# Download and install nvm
curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash

# in lieu of restarting the shell
# shellcheck disable=SC1091 # created by the nvm installer just above
\. "$HOME/.nvm/nvm.sh"

# Download and install Node.js
nvm install 24

# Verify the Node.js version
node -v

# Verify npm version
npm -v

log "Node.js installation completed successfully!"

# -----------------------------------------------------------------------------
# Install npm packages
# -----------------------------------------------------------------------------
# Codex CLI and OpenCode are the two coding agents next to Claude Code, which
# has its own installer below. pyright and typescript-language-server (with
# typescript) are the servers the pyright-lsp and typescript-lsp Claude Code
# plugins from setup-agents.sh expect to find on PATH.
log "Installing the npm packages..."
npm install -g \
    @openai/codex \
    opencode-ai \
    @kayvan/markdown-tree-parser \
    prettier \
    markdownlint-cli2 \
    pyright \
    typescript-language-server \
    typescript

# -----------------------------------------------------------------------------
# Install .NET 10 LTS and csharp-ls
# -----------------------------------------------------------------------------
# Installed with Microsoft's dotnet-install.sh rather than the archive's
# dotnet-sdk-10.0: Ubuntu tracks the 1xx SDK feature band, while the script
# resolves the newest band of the channel (currently 4xx), so the latest
# tooling is available the day Microsoft publishes it. The price is that apt
# knows nothing about it - update-all.sh re-runs the same install to keep up.
#
# Everything lands under ~/.dotnet, which is why DOTNET_ROOT and the PATH
# entries below are needed. libicu and libssl, which the runtime needs, come
# from setup-00-packages.sh.
DOTNET_CHANNEL="10.0"

# An archive SDK from an earlier version of this script would shadow the
# user-local one, since /usr/bin comes first on PATH.
if dpkg-query -W dotnet-sdk-10.0 > /dev/null 2>&1; then
    log "Removing the archive .NET SDK in favour of the dotnet-install.sh one..."
    sudo apt remove -y dotnet-sdk-10.0
    sudo apt autoremove -y
fi

log "Installing .NET $DOTNET_CHANNEL LTS..."
curl -fsSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel "$DOTNET_CHANNEL"

# shellcheck disable=SC2016 # written to .zshrc verbatim, expands there
if ! grep -qxF 'export DOTNET_ROOT="$HOME/.dotnet"' ~/.zshrc; then
    echo 'export DOTNET_ROOT="$HOME/.dotnet"' >> ~/.zshrc
    echo 'export PATH="$PATH:$DOTNET_ROOT"' >> ~/.zshrc
fi
export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$PATH:$DOTNET_ROOT"
dotnet --version

# csharp-ls is the server the csharp-lsp Claude Code plugin expects. Global
# tools land in ~/.dotnet/tools, which nothing else puts on PATH.
log "Installing csharp-ls..."
if dotnet tool list --global | grep -q '^csharp-ls '; then
    dotnet tool update --global csharp-ls
else
    dotnet tool install --global csharp-ls
fi

# shellcheck disable=SC2016 # written to .zshrc verbatim, expands there
if ! grep -qxF 'export PATH="$PATH:$HOME/.dotnet/tools"' ~/.zshrc; then
    echo 'export PATH="$PATH:$HOME/.dotnet/tools"' >> ~/.zshrc
fi
export PATH="$PATH:$HOME/.dotnet/tools"

log ".NET installation completed successfully!"

# -----------------------------------------------------------------------------
# Install Claude Code
# -----------------------------------------------------------------------------
# The installer drops the binary in ~/.local/bin, which setup-00-packages.sh
# already puts on PATH.
log "Installing Claude Code..."
curl -fsSL https://claude.ai/install.sh | bash
export PATH="$HOME/.local/bin:$PATH"

log "Claude Code installation completed successfully!"

# -----------------------------------------------------------------------------
# Install herdr
# -----------------------------------------------------------------------------
# herdr (https://herdr.dev) is a terminal workspace manager for AI coding
# agents. It is a single ~21 MB static binary, not a package - there is no apt
# repository and no dpkg entry for it.
#
# The installer drops the binary in $HOME/.local/bin (override with
# HERDR_INSTALL_DIR), which setup-00-packages.sh already puts on PATH, so no
# second PATH entry is added here.
#
# It updates itself with "herdr update" - which update-all.sh runs - and
# switches release channels with "herdr channel set stable|preview".
# Its config lives at ~/.config/herdr/config.toml.
if command -v herdr > /dev/null 2>&1; then
    log "herdr is already installed ($(herdr --version)). Skipping the installer."
    log "Update it with: herdr update"
else
    log "Installing herdr..."
    curl -fsSL https://herdr.dev/install.sh | sh
fi

# The Zsh completion is generated by herdr itself. It goes into Oh My Zsh's
# custom/completions directory, which oh-my-zsh.sh puts on fpath BEFORE it
# runs compinit - a directory appended to fpath from the end of .zshrc would be
# too late, compinit only registers what is on fpath when it runs. Regenerating
# it on every run keeps it in step with whatever version is installed.
log "Installing the herdr Zsh completion..."
ZSH_COMPLETIONS="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/completions"
mkdir -p "$ZSH_COMPLETIONS"
herdr completion zsh > "$ZSH_COMPLETIONS/_herdr"
chmod 644 "$ZSH_COMPLETIONS/_herdr"

herdr --version
log "herdr installation completed successfully!"

# -----------------------------------------------------------------------------
# Register update-sys and update-all aliases in .zshrc
# -----------------------------------------------------------------------------
log "Installing update-sys and update-all aliases in .zshrc..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

chmod +x "$SCRIPT_DIR/update-sys.sh"
chmod +x "$SCRIPT_DIR/update-all.sh"

if ! grep -q "alias update-sys=" ~/.zshrc; then
    echo "alias update-sys='$SCRIPT_DIR/update-sys.sh'" >> ~/.zshrc
    log "Added update-sys alias to .zshrc."
else
    log "update-sys alias already exists in .zshrc."
fi

if ! grep -q "alias update-all=" ~/.zshrc; then
    echo "alias update-all='$SCRIPT_DIR/update-all.sh'" >> ~/.zshrc
    log "Added update-all alias to .zshrc."
else
    log "update-all alias already exists in .zshrc."
fi

log "Aliases registered successfully!"

setup_end

# -----------------------------------------------------------------------------
# Reboot after installation
# -----------------------------------------------------------------------------
read -r -p "Reboot? (j/N): " reply
if [[ "$reply" =~ ^[JjYy]$ ]]; then
    echo "Rebooting..."
    exec sudo /sbin/reboot now
fi
