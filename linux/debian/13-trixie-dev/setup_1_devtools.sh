#!/bin/bash
set -e;

# =========================================================================
# This script performs the following tasks:
# - Installs Docker Engine and Containerd
# - Installs Google Chrome
# - Installs Visual Studio Code
# - Installs latest Node.js LTS using nvm
# - Installs npm packages (Angular CLI, Codex CLI, markdown-tree-parser)
# - Installs .NET 10 LTS
# - Installs Claude Code
# - Registers upd and updall aliases in .zshrc
# =========================================================================

# ------------------------------------
# Install Docker Engine and Containerd
# ------------------------------------

# uninstall all conflicting packages
for pkg in docker.io docker-doc docker-compose podman-docker containerd runc; do sudo apt remove $pkg; done

# Add Docker's official GPG key:
sudo apt update;
sudo apt install ca-certificates curl;
sudo install -m 0755 -d /etc/apt/keyrings;
sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc;
sudo chmod a+r /etc/apt/keyrings/docker.asc;

# Add the repository to Apt sources:
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update;

# Install latest version of Docker Engine and containerd
sudo apt -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin;

# Post-installation steps: manage Docker as a non-root user
sudo groupadd docker || true;
sudo usermod -aG docker $USER;

# ---------------------
# Install Google Chrome
# ---------------------

# Add Google signing key and repository
echo "Downloading and installing Google signing key...";
wget -qO- https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor > google-chrome.gpg;
sudo install -D -o root -g root -m 644 google-chrome.gpg /usr/share/keyrings/google-chrome.gpg;
rm -f google-chrome.gpg;

# Add Google Chrome repository to sources list
echo "Creating deb822-style source file for Google Chrome...";
sudo tee /etc/apt/sources.list.d/google-chrome.sources <<EOF
Types: deb
URIs: http://dl.google.com/linux/chrome/deb/
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/google-chrome.gpg
EOF

# Update package list
echo "Updating package list with Google repository...";
sudo apt update -y;

# Install Google Chrome stable version
echo "Installing Google Chrome (stable)...";
sudo apt install -y google-chrome-stable;

# Remove the .list file auto-created by Chrome's post-install script (duplicate of .sources)
sudo rm -f /etc/apt/sources.list.d/google-chrome.list;

# Verify installation
echo "Google Chrome installation completed successfully!";
google-chrome --version;

# --------------------------
# Install Visual Studio Code
# --------------------------

# Import the Microsoft GPG key
wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.gpg;
sudo install -D -o root -g root -m 644 microsoft.gpg /usr/share/keyrings/microsoft.gpg;
rm -f microsoft.gpg;

# Add the VS Code repository to the sources list
sudo tee /etc/apt/sources.list.d/vscode.sources <<EOF
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: /usr/share/keyrings/microsoft.gpg
EOF

# Update package lists and install VS Code
sudo apt update;
sudo apt install code;

# -----------------------------------
# Install latest NodeJS LTS using nvm
# -----------------------------------
echo "Installing NodeJS...";

# Download and install nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.4/install.sh | bash;

# in lieu of restarting the shell
\. "$HOME/.nvm/nvm.sh";

# Download and install Node.js
nvm install 24;

# Verify the Node.js version
node -v;

# Verify npm version
npm -v;

echo "Node.js installation completed successfully!";

# --------------------
# Install npm packages
# --------------------

# Install Angular CLI
echo "Installing Angular CLI...";
npm install -g @angular/cli;

# Install Codex CLI
echo "Installing Codex CLI...";
npm install -g @openai/codex;

# Install markdown-tree-parser
echo "Installing markdown-tree-parser...";
npm install -g @kayvan/markdown-tree-parser;

# ---------------------
# Install .NET 10 LTS
# ---------------------
echo "Installing .NET 10 LTS...";
curl -sSL https://dot.net/v1/dotnet-install.sh | bash /dev/stdin --channel LTS;

echo 'export DOTNET_ROOT=$HOME/.dotnet' >> ~/.zshrc;
echo 'export PATH=$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools' >> ~/.zshrc;
export DOTNET_ROOT=$HOME/.dotnet;
export PATH=$PATH:$DOTNET_ROOT:$DOTNET_ROOT/tools;

dotnet --version;
echo ".NET installation completed successfully!";

# -------------------
# Install Claude Code
# -------------------
echo "Installing Claude Code...";
curl -fsSL https://claude.ai/install.sh | bash;

echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc;
export PATH="$HOME/.local/bin:$PATH";

echo "Claude Code installation completed successfully!";

# -----------------------------------------
# Register upd and updall aliases in .zshrc
# -----------------------------------------
echo "Installing upd and updall aliases in .zshrc...";

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";

chmod +x "$SCRIPT_DIR/upd.sh";
chmod +x "$SCRIPT_DIR/updall.sh";

if ! grep -q "alias upd=" ~/.zshrc; then
    echo "alias upd='$SCRIPT_DIR/upd.sh'" >> ~/.zshrc;
    echo "Added upd alias to .zshrc.";
else
    echo "upd alias already exists in .zshrc.";
fi

if ! grep -q "alias updall=" ~/.zshrc; then
    echo "alias updall='$SCRIPT_DIR/updall.sh'" >> ~/.zshrc;
    echo "Added updall alias to .zshrc.";
else
    echo "updall alias already exists in .zshrc.";
fi

echo "Aliases registered successfully!";

# -------------------------
# Reboot after installation
# -------------------------
read -r -p "Reboot? (j/N): " reply;
if [[ "$reply" =~ ^[JjYy]$ ]]; then
    echo "Rebooting...";
    exec sudo /sbin/reboot now;
fi
