#!/bin/bash
set -euo pipefail

# =============================================================================
# This script performs the following tasks:
# - Installs Docker Engine and Containerd
# - Installs Neovim
# - Installs lazygit, lazydocker and dive
# - Installs yq (the Go one) and its Zsh completion
# - Installs Google Chrome
# - Installs Visual Studio Code
# - Installs Orca ADE
# - Installs JetBrains Toolbox
# - Installs GitHub CLI
# - Installs Node.js 24 using nvm
# - Installs npm packages (Codex CLI, OpenCode, markdown-tree-parser,
#   Prettier, markdownlint-cli2, the Pyright and TypeScript language
#   servers)
# - Installs uv (Python packages, projects and interpreters) and Ruff, the
#   Python linter and formatter, with their Zsh completions
# - Installs .NET 10 LTS with Microsoft's dotnet-install.sh and the csharp-ls
#   language server
# - Installs Claude Code
# - Installs herdr and its Zsh completion
# - Registers update-sys and update-all aliases in .zshrc
# - Reboots the system after installation
# =============================================================================

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
setup_begin "$@"
sudo_keepalive

# Nothing between here and the end leaves the machine untouched - it writes an apt source
# straight away - so the completion marker goes now.
setup_invalidate

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
step "Install Docker Engine and Containerd"

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
step "Install Neovim"
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

# The .zshrc entry above only reaches an interactive zsh. Anything else that
# wants an editor - Git called from VS Code, JetBrains or a hook, a shell
# script, cron - searches a PATH that has never seen /opt, and "nvim" is then
# simply not found. So it is linked into ~/.local/bin as well, the same way
# orca-ide, claude and herdr are, which setup-00-packages.sh put on PATH.
# This is what lets setup-07-git.sh set core.editor to a bare "nvim".
mkdir -p "$HOME/.local/bin"
ln -sfn "$NVIM_PREFIX/bin/nvim" "$HOME/.local/bin/nvim"
log "Linked nvim into ~/.local/bin."

nvim --version | head -1

# -----------------------------------------------------------------------------
# Install lazygit
# -----------------------------------------------------------------------------
# Installed from its GitHub releases rather than the archive, whose version
# is pinned for the lifetime of the release. update-all.sh refreshes it.
step "Install lazygit"
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
step "Install lazydocker"
log "Installing lazydocker..."

LAZYDOCKER_VERSION="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazydocker/releases/latest | grep -Po '"tag_name": *"v\K[^"]*')"
curl -fsSL -o /tmp/lazydocker.tar.gz "https://github.com/jesseduffield/lazydocker/releases/download/v${LAZYDOCKER_VERSION}/lazydocker_${LAZYDOCKER_VERSION}_Linux_x86_64.tar.gz"
tar -C /tmp -xzf /tmp/lazydocker.tar.gz lazydocker
sudo install -m 0755 /tmp/lazydocker /usr/local/bin/lazydocker
rm -f /tmp/lazydocker.tar.gz /tmp/lazydocker

lazydocker --version | head -1

# -----------------------------------------------------------------------------
# Install dive
# -----------------------------------------------------------------------------
# dive explores a Docker image one layer at a time, showing what each layer
# added and which files a later layer made redundant - the one thing lazydocker
# above does not do. Installed from its GitHub releases like lazygit and
# lazydocker, since Ubuntu does not package it; update-all.sh refreshes it.
#
# The release carries a .deb as well, but the tarball is used for the same
# reason it is for the other two: nothing else here needs dpkg to know about
# the binary, and /usr/local/bin keeps all three together.
step "Install dive"
log "Installing dive..."

DIVE_VERSION="$(curl -fsSL https://api.github.com/repos/wagoodman/dive/releases/latest | grep -Po '"tag_name": *"v\K[^"]*')"
curl -fsSL -o /tmp/dive.tar.gz "https://github.com/wagoodman/dive/releases/download/v${DIVE_VERSION}/dive_${DIVE_VERSION}_linux_amd64.tar.gz"
tar -C /tmp -xzf /tmp/dive.tar.gz dive
sudo install -m 0755 /tmp/dive /usr/local/bin/dive
rm -f /tmp/dive.tar.gz /tmp/dive

dive --version

# -----------------------------------------------------------------------------
# Install yq
# -----------------------------------------------------------------------------
# yq is jq for YAML. Which yq matters: two unrelated programs answer to that
# name, and the one in the archive is kislyuk's Python wrapper around jq, whose
# expression syntax is jq's. This installs mikefarah's Go implementation - the
# one nearly all documentation and answers online assume - whose syntax is its
# own. Mixing them up costs an afternoon, so the archive package is removed
# below if it is there.
#
# From its GitHub releases like lazygit, lazydocker and dive above; the asset
# is a bare binary rather than a tarball, so there is nothing to unpack.
# update-all.sh refreshes it.
step "Install yq"
log "Installing yq..."

# The archive package owns /usr/bin/yq. /usr/local/bin comes first on PATH, so
# the one installed here would win either way, but leaving both would mean a
# script or a root shell with a different PATH silently getting the other tool.
if dpkg-query -W -f='${Status}' yq 2> /dev/null | grep -q '^install ok installed'; then
    log "  Removing the archive yq (the Python one) in favour of the Go one..."
    sudo apt remove -y yq
    sudo apt autoremove -y
fi

YQ_VERSION="$(curl -fsSL https://api.github.com/repos/mikefarah/yq/releases/latest | grep -Po '"tag_name": *"v\K[^"]*')"
curl -fsSL -o /tmp/yq "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64"
sudo install -m 0755 /tmp/yq /usr/local/bin/yq
rm -f /tmp/yq

# Generated by yq itself, into the same Oh My Zsh completions directory the uv
# and herdr ones use - see the herdr section for why it has to be there.
YQ_ZSH_COMPLETIONS="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/completions"
mkdir -p "$YQ_ZSH_COMPLETIONS"
yq shell-completion zsh > "$YQ_ZSH_COMPLETIONS/_yq"
chmod 644 "$YQ_ZSH_COMPLETIONS/_yq"

yq --version

# -----------------------------------------------------------------------------
# Install Google Chrome
# -----------------------------------------------------------------------------
step "Install Google Chrome"

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
step "Install Visual Studio Code"
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
step "Install Orca ADE"
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
# Install JetBrains Toolbox
# -----------------------------------------------------------------------------
# Through the community installer, pinned to a commit. CI=1 stops it from
# launching Toolbox itself: it does so with a bare "&", leaving the app
# attached to the terminal, so its output lands on the prompt and, worse,
# whatever captures this script's output (a pipe, tee, a log) waits until
# Toolbox exits. The launch happens below instead, detached.
step "Install JetBrains Toolbox"
curl -fsSL https://raw.githubusercontent.com/nagygergo/jetbrains-toolbox-install/4184247d1d12888024181f27dea7b7868d8f9e81/jetbrains-toolbox.sh | CI=1 bash

# The first launch is what writes the .desktop file (setup-06-configs.sh pins
# it to the dock) and the autostart entry, so it has to happen. setsid puts
# Toolbox in its own session, -f forks so this script does not wait, and the
# redirections cut it off the terminal - nothing is left to press Enter for.
log "Launching JetBrains Toolbox for its first-time setup..."
setsid -f "$HOME/.local/share/JetBrains/Toolbox/bin/jetbrains-toolbox" \
    < /dev/null > /dev/null 2>&1

# -----------------------------------------------------------------------------
# Install GitHub CLI
# -----------------------------------------------------------------------------
step "Install GitHub CLI"
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
step "Install Node.js 24 using nvm"
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
step "Install npm packages"
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
# Install uv
# -----------------------------------------------------------------------------
# uv (https://docs.astral.sh/uv) is the Python side of this setup: it installs
# packages, manages per-project virtualenvs and downloads interpreters, none of
# which the archive's python3-pip and python3-venv do well. It also brings
# uvx, which runs a Python tool in a throwaway environment without installing
# anything first. Ruff, below, is installed properly rather than run that way,
# because an editor has to find it on PATH.
#
# Installed with the Astral installer rather than from apt: it is a single
# static binary that updates itself with "uv self update", which update-all.sh
# runs, while the archive version would be frozen for the life of the release.
#
# INSTALLER_NO_MODIFY_PATH=1 because the installer would otherwise append its
# own PATH line to the shell profile. It installs into ~/.local/bin, which
# setup-00-packages.sh has already put on PATH, so that line would be a
# duplicate entry pointing at the same directory.
step "Install uv"
if command -v uv > /dev/null 2>&1; then
    log "uv is already installed ($(uv --version)). Skipping the installer."
    log "Update it with: uv self update"
else
    log "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | env INSTALLER_NO_MODIFY_PATH=1 sh
fi

# Everything below calls uv, and Ruff calls the shim uv puts here, in the same
# run that installed them. setup-00-packages.sh only exported ~/.local/bin into
# its own process, so a machine set up in one sitting - without the logout that
# picks up the .zshrc entry - would reach this with the directory not on PATH
# yet. The Claude Code section does the same export further down for the same
# reason; doing it here as well costs nothing and is what makes this section
# safe to run on its own.
export PATH="$HOME/.local/bin:$PATH"

# Generated by uv itself, into the same Oh My Zsh completions directory the
# herdr completion below uses - see that section for why it has to be there
# rather than appended to .zshrc. uv and uvx carry separate completions.
log "Installing the uv Zsh completions..."
UV_ZSH_COMPLETIONS="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/completions"
mkdir -p "$UV_ZSH_COMPLETIONS"
uv generate-shell-completion zsh > "$UV_ZSH_COMPLETIONS/_uv"
uvx --generate-shell-completion zsh > "$UV_ZSH_COMPLETIONS/_uvx"
chmod 644 "$UV_ZSH_COMPLETIONS/_uv" "$UV_ZSH_COMPLETIONS/_uvx"

uv --version

# -----------------------------------------------------------------------------
# Install Ruff
# -----------------------------------------------------------------------------
# Ruff is the Python linter and formatter, and the last gap in the set: this
# machine already formats JavaScript and friends with Prettier, Markdown with
# markdownlint-cli2 and shell with shfmt, while Python had nothing.
#
# "uv tool install" rather than "uvx ruff": uvx resolves and caches the tool on
# each first use, and leaves nothing on PATH - fine for a one-off command, no
# good for something an editor, a pre-commit hook or LazyVim's formatter has to
# find by name. The shim lands in ~/.local/bin, already on PATH from
# setup-00-packages.sh, and update-all.sh upgrades it.
#
# Checked before installing, the same way csharp-ls is below: "uv tool install"
# on a tool that is already there does not upgrade it.
step "Install Ruff"
log "Installing Ruff..."
if uv tool list 2> /dev/null | grep -q '^ruff '; then
    uv tool upgrade ruff
else
    uv tool install ruff
fi

# Generated by Ruff itself, into the completions directory the uv ones went to.
ruff generate-shell-completion zsh > "$UV_ZSH_COMPLETIONS/_ruff"
chmod 644 "$UV_ZSH_COMPLETIONS/_ruff"

ruff --version

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
step "Install .NET 10 LTS and csharp-ls"
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
# The .NET CLI reports usage to Microsoft unless told not to. Exported here
# as well, so that the dotnet calls below - the first ones ever made - send
# nothing either.
if ! grep -qxF 'export DOTNET_CLI_TELEMETRY_OPTOUT=1' ~/.zshrc; then
    echo 'export DOTNET_CLI_TELEMETRY_OPTOUT=1' >> ~/.zshrc
fi
export DOTNET_ROOT="$HOME/.dotnet"
export PATH="$PATH:$DOTNET_ROOT"
export DOTNET_CLI_TELEMETRY_OPTOUT=1
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
step "Install Claude Code"
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
step "Install herdr"
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
step "Register update-sys and update-all aliases in .zshrc"
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
# Not a question: the changes above only take effect at the next login, and
# the next script depends on them. Enter reboots; Ctrl-C is the way out for
# whoever wants to reboot later - the completion marker is written already.
step "Reboot after installation"
log "The machine has to reboot for the changes to take effect."
read -r -p "Press Enter to reboot..."
echo "Rebooting..."
exec sudo /sbin/reboot now
