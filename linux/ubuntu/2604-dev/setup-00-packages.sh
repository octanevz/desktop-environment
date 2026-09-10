#!/bin/bash
set -euo pipefail

# =============================================================================
# This script performs the following tasks:
# - Updates the OS and installs required packages
# - Sets an English UI with German date, number and paper formats
# - Installs Oh My Zsh with autosuggestions and syntax highlighting plugins
# - Sets Zsh as the default shell
# - Aliases l, lf and ld to eza
# - Installs the LazyVim prerequisites (ripgrep, fd, fzf, tree-sitter, a Nerd
#   Font and friends)
# - Installs Tmux Plugin Manager
# - Installs the VMware guest tools in a VMware VM, proprietary drivers on
#   bare metal
# - Optionally reboots the system after installation
# =============================================================================

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
# The interface language and the formats locale are set independently, which is
# what GNOME's Region & Language panel calls "Language" and "Formats".
UI_LOCALE="en_US.UTF-8"
FORMATS_LOCALE="de_DE.UTF-8"

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
setup_begin "$@"

# -----------------------------------------------------------------------------
# Enable the universe component
# -----------------------------------------------------------------------------
# universe carries btop, eza, ripgrep, the GNOME tweak tools and friends;
# everything else below is in main. Ubuntu Desktop enables universe out of
# the box, so this is a no-op there; it matters on an install that was trimmed
# to main. -n skips the apt update add-apt-repository would otherwise run -
# the next section updates once for everything.
sudo apt install -y software-properties-common
sudo add-apt-repository -y -n universe

# -----------------------------------------------------------------------------
# Update OS and install some required packages
# -----------------------------------------------------------------------------
# Note: Ubuntu (like Debian 13) ships the 64-bit time_t transition names, so
# libfuse2t64 / liblttng-ust1t64 / libssl3t64 are used instead of the old
# libfuse2 / liblttng-ust1 / libssl3 names. libicu-dev pulls in the matching
# libicuXX runtime, so no version-pinned libicu package is listed here.
#
# desktop-file-utils is here because setup-04-alacritty.sh needs
# desktop-file-install to install what it builds, and that script performs no
# apt installs of its own. dconf-cli is here for the same reason:
# setup-06-gnome-extensions.sh loads the extension settings with it. The
# libfontconfig1, libfreetype6, libwayland-client0, libxcb-xfixes0 and
# libxkbcommon* entries are the Alacritty runtime libraries setup-04 verifies -
# see that script for why the split exists.
#
# Separate statements rather than one && chain: set -e ignores a failure
# anywhere but the last link of a chain, so a failed upgrade would otherwise
# go unnoticed.
sudo apt update -y
sudo apt upgrade -y
sudo apt install -y \
    apt-transport-https \
    bash-completion \
    btop \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    dconf-cli \
    desktop-file-utils \
    eza \
    fastfetch \
    fd-find \
    fontconfig \
    fonts-jetbrains-mono \
    fzf \
    gimp \
    git \
    gnome-keyring \
    gnome-shell-extension-manager \
    gnome-shell-extensions \
    gnome-tweaks \
    gnupg \
    libfontconfig1 \
    libfreetype6 \
    libfuse2t64 \
    libicu-dev \
    libjpeg-turbo8 \
    liblttng-ust1t64 \
    libsecret-1-0 \
    libsecret-1-dev \
    libssl3t64 \
    libwayland-client0 \
    libxcb-xfixes0 \
    libxkbcommon0 \
    libxkbcommon-x11-0 \
    locales \
    lsb-release \
    lsof \
    mesa-utils \
    nano \
    pkg-config \
    python3 \
    python3-pip \
    python3-venv \
    ripgrep \
    shellcheck \
    shfmt \
    tmux \
    tree \
    tree-sitter-cli \
    ubuntu-drivers-common \
    unzip \
    uuid-runtime \
    wget \
    wl-clipboard \
    xclip \
    zsh
sudo apt autoremove -y
sudo apt clean -y

# -----------------------------------------------------------------------------
# Configure the locale
# -----------------------------------------------------------------------------
# English interface, German formats. LANG and LANGUAGE stay en_US so menus,
# messages and man pages are English, while the categories below switch to
# de_DE for dates, 24-hour time, decimal commas, A4 paper, metric units and
# Monday as the first day of the week.
#
# FORMAT_CATEGORIES is exactly the set GNOME's own Formats setting overrides.
# The categories NOT listed - LC_CTYPE, LC_COLLATE, LC_MESSAGES, LC_NAME and
# LC_IDENTIFICATION - are deliberately left to follow LANG, and that is what
# keeps the interface English.
#
# Know one side effect before keeping LC_NUMERIC: a comma becomes the decimal
# separator for every program in the session, so "printf '%.2f' 1234.56" fails
# and tools that parse numbers in the C format can misread them. Remove
# LC_NUMERIC from the list if that gets in the way; nothing else here depends
# on it.
FORMAT_CATEGORIES=(
    LC_ADDRESS
    LC_MEASUREMENT
    LC_MONETARY
    LC_NUMERIC
    LC_PAPER
    LC_TELEPHONE
    LC_TIME
)

log "Configuring the locale ($UI_LOCALE interface, $FORMATS_LOCALE formats)..."

# Both locales are made available, not just the German one: update-locale
# validates every value it is given and refuses the entire call if any of
# them is missing, so assuming the installer already produced en_US.UTF-8
# would make this fail on an install done in another language.
#
# Ubuntu locales come from language packs, not from /etc/locale.gen: each
# language-pack-XX-base registers its locales in /var/lib/locales/supported.d
# and compiles them, and GNOME's Formats list only offers regions whose
# language pack is installed. So the pack for each locale's language is
# installed first, which also brings the translations.
#
# Do NOT edit /etc/locale.gen and run a bare "locale-gen" instead. Ubuntu's
# locale-gen pipes that file through "sort -u", and under the en_US.UTF-8
# collation the template line "# de_DE.UTF-8 UTF-8" compares equal to the
# real entry "de_DE.UTF-8 UTF-8". sort keeps the first of the two - the
# comment - and the locale is silently never generated. Called with the
# locale names as arguments, locale-gen resolves them against
# /usr/share/i18n/SUPPORTED itself, compiles them and keeps the archive,
# which is the form used here after the packs, as a belt-and-braces step.
LANGUAGE_PACKS=()
for locale_name in "$UI_LOCALE" "$FORMATS_LOCALE"; do
    LANGUAGE_PACKS+=("language-pack-${locale_name%%_*}-base")
done
log "  Installing the language packs (${LANGUAGE_PACKS[*]})..."
sudo apt install -y "${LANGUAGE_PACKS[@]}"

log "  Generating the locales..."
sudo locale-gen "$UI_LOCALE" "$FORMATS_LOCALE"

# The same check update-locale performs, so a missing locale is reported
# here by name rather than as a rejected update-locale call further down.
for locale_name in "$UI_LOCALE" "$FORMATS_LOCALE"; do
    if ! LC_ALL="$locale_name" locale charmap > /dev/null 2>&1; then
        echo "The locale $locale_name is not available after locale-gen." >&2
        echo "Check the locale-gen output above; 'locale -a' lists what exists." >&2
        exit 1
    fi
done

# update-locale writes /etc/locale.conf (Ubuntu 26.04 links the old
# /etc/default/locale to it), which PAM puts into the environment of every
# login - terminals, SSH sessions and cron alike.
LOCALE_ASSIGNMENTS=(
    "LANG=$UI_LOCALE"
    "LANGUAGE=${UI_LOCALE%%.*}:${UI_LOCALE%%_*}"
)
for category in "${FORMAT_CATEGORIES[@]}"; do
    LOCALE_ASSIGNMENTS+=("$category=$FORMATS_LOCALE")
done

sudo update-locale "${LOCALE_ASSIGNMENTS[@]}"
log "  Wrote /etc/locale.conf."

# GNOME does not take its formats from /etc/locale.conf: gnome-session
# exports the same categories from its own Formats setting, so that has to be
# set as well or the desktop session would quietly override what was just
# written. The two are set from the same variables above, so they cannot drift.
#
# The schema is org.gnome.system.locale, but the dconf path behind it is the
# legacy /system/locale/ - NOT /org/gnome/system/locale/ - which is why the
# write below names that path. It is written with dconf rather than gsettings
# set: gsettings exits 0 even when it could not reach dconf (it only prints a
# warning), so its status says nothing, whereas dconf write fails properly and
# the fallback below can trigger. Both tools need the session bus to write.
if gsettings list-schemas 2> /dev/null | grep -x "org.gnome.system.locale" > /dev/null; then
    if dconf write /system/locale/region "'$FORMATS_LOCALE'" 2> /dev/null; then
        log "  Set the GNOME Formats region to $FORMATS_LOCALE."
    else
        log "  Could not reach dconf. Inside a desktop session, run:"
        log "    gsettings set org.gnome.system.locale region $FORMATS_LOCALE"
    fi
else
    log "  No GNOME schemas found - skipping the desktop Formats setting."
fi

log "  Log out and back in for the new locale to take effect."

# -----------------------------------------------------------------------------
# Install Oh My Zsh and plugins
# -----------------------------------------------------------------------------

# Install Oh My Zsh if not already installed
if [ -d "$HOME/.oh-my-zsh" ]; then
    log "Oh My Zsh is already installed at $HOME/.oh-my-zsh. Skipping installation."
else
    log "Installing Oh My Zsh..."
    # Downloaded into a variable first: a failed substitution inside a command
    # argument does not trip set -e, and sh -c "" would "succeed" silently.
    OMZ_INSTALLER="$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    sh -c "$OMZ_INSTALLER" "" --unattended
fi

# Set Zsh as the default shell (chsh asks for a password, so only when needed)
if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$(which zsh)" ]; then
    log "Setting Zsh as the default shell..."
    chsh -s "$(which zsh)"
else
    log "Zsh is already the default shell."
fi

# Install Zsh autosuggestions
if [ ! -d "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions" ]; then
    log "Installing Zsh autosuggestions..."
    git clone https://github.com/zsh-users/zsh-autosuggestions "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
else
    log "Zsh autosuggestions already installed. Skipping."
fi

# Install Zsh syntax highlighting
if [ ! -d "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" ]; then
    log "Installing Zsh syntax highlighting..."
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
else
    log "Zsh syntax highlighting already installed. Skipping."
fi

# Update .zshrc to enable plugins
log "Configuring Zsh plugins in .zshrc..."
if ! grep -q "zsh-autosuggestions" ~/.zshrc; then
    sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting)/' ~/.zshrc
fi

# The sed only knows the stock template line, so verify the result instead of
# trusting it: read the entries between the parentheses of the active plugins=
# line and check each plugin is one of them. A mention in a comment does not
# count, which is why this does not grep the whole file.
ZSH_PLUGINS="$(sed -n 's/^plugins=(\([^)]*\)).*/\1/p' ~/.zshrc)"
for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
    if [[ " $ZSH_PLUGINS " == *" $plugin "* ]]; then
        log "$plugin is enabled in .zshrc."
    else
        log "Could not enable $plugin - add it to the plugins=(...) line in ~/.zshrc by hand."
    fi
done

# -----------------------------------------------------------------------------
# Alias l, lf and ld to eza
# -----------------------------------------------------------------------------
# eza (installed above) replaces the ls behind Oh My Zsh's l alias: icons and
# colours whether or not the output is a terminal, file names as clickable
# hyperlinks, and ISO timestamps. lf lists only files and ld only
# directories. Appended after the Oh My Zsh block, so l overrides the alias
# Oh My Zsh defines.
log "Aliasing l, lf and ld to eza in .zshrc..."
EZA_OPTS="--icons=always -la --color=always --hyperlink --time-style long-iso"
EZA_ALIASES=(
    "l=$EZA_OPTS"
    "lf=$EZA_OPTS --only-files"
    "ld=$EZA_OPTS --only-dirs"
)
for entry in "${EZA_ALIASES[@]}"; do
    name="${entry%%=*}"
    if ! grep -q "^alias $name=" ~/.zshrc; then
        echo "alias $name='eza ${entry#*=}'" >> ~/.zshrc
        log "Added $name alias to .zshrc."
    else
        log "$name alias already exists in .zshrc."
    fi
done

# -----------------------------------------------------------------------------
# Install Nerd Fonts
# -----------------------------------------------------------------------------
# fonts-jetbrains-mono (installed above) provides the text face; the Nerd Font
# symbol-only patch supplies the icons LazyVim and the Tmux theme render.
log "Installing Nerd Font symbols..."

FONT_DIR="$HOME/.local/share/fonts/SymbolsNerdFont"
mkdir -p "$FONT_DIR"
curl -fsSL -o /tmp/NerdFontsSymbolsOnly.zip https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.zip
unzip -oq /tmp/NerdFontsSymbolsOnly.zip -d "$FONT_DIR"
rm -f /tmp/NerdFontsSymbolsOnly.zip
fc-cache -f "$HOME/.local/share/fonts" > /dev/null

log "Nerd Font symbols installed."

# -----------------------------------------------------------------------------
# Install fd shim for LazyVim
# -----------------------------------------------------------------------------
# Ubuntu ships the fd binary as fdfind; a lot of tooling looks for plain "fd".
if [ ! -e "$HOME/.local/bin/fd" ]; then
    log "Linking fdfind as fd in ~/.local/bin..."
    mkdir -p "$HOME/.local/bin"
    ln -s "$(which fdfind)" "$HOME/.local/bin/fd"
else
    log "fd shim already present. Skipping."
fi

# Matched as the exact line: the Oh My Zsh template already mentions
# $HOME/.local/bin in a commented-out example, which a looser grep would take
# for the real thing. setup-01-devtools.sh relies on this entry for everything
# it puts in ~/.local/bin (orca-ide, claude, herdr).
# shellcheck disable=SC2016 # written to .zshrc verbatim, expands there
if ! grep -qxF 'export PATH="$HOME/.local/bin:$PATH"' ~/.zshrc; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
fi
export PATH="$HOME/.local/bin:$PATH"

# -----------------------------------------------------------------------------
# Install Tmux Plugin Manager
# -----------------------------------------------------------------------------
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    log "Installing Tmux Plugin Manager..."
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
else
    log "Tmux Plugin Manager already installed. Skipping."
fi

# -----------------------------------------------------------------------------
# Install the hardware-specific packages
# -----------------------------------------------------------------------------
# What is worth installing depends on what the machine is: the VMware guest
# tools only do anything under VMware, and ubuntu-drivers (an Ubuntu-only tool)
# only makes sense on bare metal. systemd-detect-virt exits non-zero on bare
# metal, hence the || true.
VIRT="$(systemd-detect-virt || true)"
case "$VIRT" in
    vmware)
        log "VMware guest detected - installing open-vm-tools-desktop..."
        sudo apt install -y open-vm-tools-desktop
        ;;
    none)
        log "Bare metal detected - installing recommended proprietary drivers..."
        sudo ubuntu-drivers install || log "No additional drivers were installed."
        ;;
    *)
        log "Virtual machine detected ($VIRT). Nothing hardware-specific to install."
        ;;
esac

# -----------------------------------------------------------------------------
# Remove the Firefox snap (opt-in only)
# -----------------------------------------------------------------------------
# Ubuntu Desktop ships Firefox as a snap. Google Chrome is installed by
# setup-01-devtools.sh, so the snap is redundant - but removing it deletes the
# profile, so it only happens when explicitly requested:
#   REMOVE_FIREFOX_SNAP=1 ./setup-00-packages.sh
if [ "${REMOVE_FIREFOX_SNAP:-0}" = "1" ] && snap list firefox > /dev/null 2>&1; then
    log "Removing the Firefox snap..."
    sudo snap remove --purge firefox
else
    log "Keeping the Firefox snap (set REMOVE_FIREFOX_SNAP=1 to remove it)."
fi

setup_end

# -----------------------------------------------------------------------------
# Reboot after installation
# -----------------------------------------------------------------------------
read -r -p "Reboot? (j/N): " reply
if [[ "$reply" =~ ^[JjYy]$ ]]; then
    echo "Rebooting..."
    exec sudo /sbin/reboot now
fi
