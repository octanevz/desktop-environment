#!/bin/bash
set -euo pipefail

# =============================================================================
# This script performs the following tasks:
# - Updates the OS and installs required packages
# - Sets an English UI with German date, number and paper formats
# - Installs Oh My Zsh with autosuggestions and syntax highlighting plugins
# - Sets Zsh as the default shell
# - Aliases l, lf and ld to eza
# - Sets up atuin as the Ctrl-R shell history
# - Sets up zoxide as the z directory jumper
# - Binds the fzf key bindings and points them at fd and bat
# - Hooks direnv into the shell
# - Installs the LazyVim prerequisites (ripgrep, fd, fzf, tree-sitter, a Nerd
#   Font and friends)
# - Shims fdfind as fd and batcat as bat in ~/.local/bin
# - Installs Tmux Plugin Manager
# - Installs the VMware guest tools in a VMware VM, proprietary drivers on
#   bare metal
# - Reboots the system after installation
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

# Nothing between here and the end leaves the machine untouched - it installs packages
# straight away - so the completion marker goes now.
setup_invalidate

# -----------------------------------------------------------------------------
# Enable the universe component
# -----------------------------------------------------------------------------
# universe carries btop, eza, ripgrep, the GNOME tweak tools and friends;
# everything else below is in main. Ubuntu Desktop enables universe out of
# the box, so this is a no-op there; it matters on an install that was trimmed
# to main. -n skips the apt update add-apt-repository would otherwise run -
# the next section updates once for everything.
step "Enable the universe component"
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
# setup-06-gnome-extensions.sh loads the extension settings with it, and
# git-delta for setup-08-git.sh, which points the Git pager at it. The
# libfontconfig1, libfreetype6, libwayland-client0, libxcb-xfixes0 and
# libxkbcommon* entries are the Alacritty runtime libraries setup-04 verifies -
# see that script for why the split exists.
#
# Separate statements rather than one && chain: set -e ignores a failure
# anywhere but the last link of a chain, so a failed upgrade would otherwise
# go unnoticed.
step "Update OS and install some required packages"
sudo apt update -y
sudo apt upgrade -y
sudo apt install -y \
    apt-transport-https \
    atuin \
    bash-completion \
    bat \
    btop \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    dconf-cli \
    desktop-file-utils \
    direnv \
    duf \
    entr \
    eza \
    fastfetch \
    fd-find \
    ffmpeg \
    fontconfig \
    fonts-jetbrains-mono \
    fzf \
    gimp \
    git \
    git-absorb \
    git-delta \
    git-lfs \
    gitleaks \
    glow \
    gnome-keyring \
    gnome-shell-extension-manager \
    gnome-shell-extensions \
    gnome-tweaks \
    gnupg \
    hyperfine \
    imagemagick \
    jq \
    just \
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
    ncdu \
    pkg-config \
    postgresql-client \
    pre-commit \
    python3 \
    python3-pip \
    python3-venv \
    ripgrep \
    rsync \
    shellcheck \
    shfmt \
    sqlite3 \
    tealdeer \
    tmux \
    tree \
    tree-sitter-cli \
    ubuntu-drivers-common \
    unzip \
    uuid-runtime \
    wget \
    wl-clipboard \
    xclip \
    zoxide \
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
step "Configure the locale"
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
step "Install Oh My Zsh and plugins"

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
step "Alias l, lf and ld to eza"
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
# Configure the fzf key bindings
# -----------------------------------------------------------------------------
# fzf is installed above but binds nothing on its own - the package ships the
# integration and leaves enabling it to the user, so without this Ctrl-T (put a
# file path on the command line) and Alt-C (cd into a subdirectory) do nothing.
#
# This block is deliberately written to .zshrc BEFORE the atuin one below.
# "fzf --zsh" also binds Ctrl-R to fzf's own history search, and the later of
# the two bindings wins - so with the order reversed, fzf would quietly take
# Ctrl-R back off atuin. Keep these two sections in this order.
#
# The commands are pointed at fd rather than fzf's default find walk, which
# means .gitignore is respected and .git is skipped, and the previews use bat
# and eza. All three are installed above; fd and bat are reached through the
# shims further down, which is why nothing here calls fdfind or batcat.
step "Configure the fzf key bindings"
log "Configuring the fzf key bindings..."

# "fzf --zsh" prints the integration; it exists from fzf 0.48 on. Checked
# rather than assumed, because a .zshrc line calling a flag the local fzf does
# not know would print an error on every single shell start.
if ! fzf --zsh > /dev/null 2>&1; then
    log "  This fzf does not support 'fzf --zsh' - skipping the key bindings."
elif grep -qxF 'source <(fzf --zsh)' ~/.zshrc; then
    log "  The fzf key bindings are already in .zshrc."
else
    # A quoted heredoc, not the line-by-line loop used elsewhere in this
    # script: these lines nest single inside double quotes, which survives
    # verbatim here and would need escaping anywhere else.
    cat >> ~/.zshrc << 'EOF'

# fzf: Ctrl-T inserts a file path, Alt-C changes directory. Ctrl-R belongs to
# atuin, bound below this line.
export FZF_DEFAULT_COMMAND='fd --type f --hidden --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_CTRL_T_OPTS="--preview 'bat -n --color=always {}'"
export FZF_ALT_C_COMMAND='fd --type d --hidden --exclude .git'
export FZF_ALT_C_OPTS="--preview 'eza --icons=always -la --color=always {}'"
source <(fzf --zsh)
EOF
    log "  Added the fzf key bindings to .zshrc."
fi

# -----------------------------------------------------------------------------
# Configure atuin as the Ctrl-R shell history
# -----------------------------------------------------------------------------
# atuin (installed above) replaces the Ctrl-R history search with a search over
# a SQLite database that also records the working directory, the exit code and
# the duration of every command. The database matters beyond the extra columns:
# ~/.zsh_history is one file that every shell appends to, so parallel tmux
# panes overwrite each other's history, and a pane brought back by
# tmux-resurrect starts out with none of it. atuin has neither problem.
#
# Sync is opt-in and stays off unless "atuin register" is run - nothing here
# contacts a server, and the database never leaves the machine.
step "Configure atuin as the Ctrl-R shell history"
log "Configuring atuin..."

# The config is only written when there is none, so later hand edits survive a
# re-run. history_filter is the reason not to skip it: gh, claude and the
# installer curls all put credentials on the command line sooner or later, and
# a filtered command is never recorded in the first place.
ATUIN_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/atuin"
if [ ! -f "$ATUIN_CONFIG_DIR/config.toml" ]; then
    mkdir -p "$ATUIN_CONFIG_DIR"
    cat > "$ATUIN_CONFIG_DIR/config.toml" << 'EOF'
# Search below the prompt rather than taking over the screen.
inline_height = 20
style = "compact"
search_mode = "fuzzy"

# Enter runs the selected command; Tab puts it on the prompt to edit first.
enter_accept = true

# Commands matching these are never written to the history database.
history_filter = [
  "(?i)^curl .*(token|key|secret|password)",
  "(?i)^export .*(TOKEN|KEY|SECRET|PASSWORD)",
]
EOF
    log "  Wrote $ATUIN_CONFIG_DIR/config.toml."
else
    log "  $ATUIN_CONFIG_DIR/config.toml already exists. Keeping it."
fi

# Imported before the shell integration is in place, so the existing history is
# already searchable the first time Ctrl-R is pressed. Only on the first run:
# an import is not idempotent, so running it again would duplicate every entry.
# "atuin import auto" is deliberately not used - it picks the importer from
# $SHELL, which is whatever shell this script was started from, and the chsh
# above has just made that stale.
if [ ! -e "${XDG_DATA_HOME:-$HOME/.local/share}/atuin/history.db" ]; then
    for shell_name in zsh bash; do
        if [ -s "$HOME/.${shell_name}_history" ]; then
            log "  Importing the $shell_name history..."
            atuin import "$shell_name" || log "  Could not import it - run 'atuin import $shell_name' by hand."
        fi
    done
else
    log "  The atuin database already exists - not importing again."
fi

# Appended after the Oh My Zsh block for the same reason the eza aliases are:
# the init binds Ctrl-R, and anything Oh My Zsh binds has to be in place first.
#
# --disable-up-arrow keeps the arrow key on plain "previous command" and leaves
# atuin on Ctrl-R alone. Drop the flag to have the arrow open atuin too,
# filtered to the current directory.
# shellcheck disable=SC2016 # written to .zshrc verbatim, expands there
ATUIN_INIT='eval "$(atuin init zsh --disable-up-arrow)"'
if ! grep -qxF "$ATUIN_INIT" ~/.zshrc; then
    echo "$ATUIN_INIT" >> ~/.zshrc
    log "  Added the atuin init to .zshrc."
else
    log "  The atuin init is already in .zshrc."
fi

atuin --version

# -----------------------------------------------------------------------------
# Configure zoxide as the z directory jumper
# -----------------------------------------------------------------------------
# zoxide (installed above) learns the directories that are actually visited and
# adds "z", which jumps to the best match for a fragment of a path - "z herdr"
# rather than the full path to it - and "zi", which picks one interactively
# through fzf, installed above. cd is left alone, so nothing that already works
# changes; pass --cmd cd below to have z take cd over entirely.
#
# Appended after the Oh My Zsh block like the entries above, and for one extra
# reason: the init defines completions, and compinit - which oh-my-zsh.sh runs -
# has to have gone first for them to register.
step "Configure zoxide as the z directory jumper"
log "Configuring zoxide..."

# shellcheck disable=SC2016 # written to .zshrc verbatim, expands there
ZOXIDE_INIT='eval "$(zoxide init zsh)"'
if ! grep -qxF "$ZOXIDE_INIT" ~/.zshrc; then
    echo "$ZOXIDE_INIT" >> ~/.zshrc
    log "  Added the zoxide init to .zshrc."
else
    log "  The zoxide init is already in .zshrc."
fi

zoxide --version

# -----------------------------------------------------------------------------
# Hook direnv into the shell
# -----------------------------------------------------------------------------
# direnv (installed above) loads and unloads environment variables per
# directory from an .envrc file, which is what keeps per-project settings out
# of .zshrc now that nvm, uv and ~/.dotnet all live on this machine. An .envrc
# does nothing until it is allowed once with "direnv allow", so a repository
# cloned from anywhere cannot change the environment behind one's back.
#
# The hook goes last of the four appended to .zshrc. Its own position among
# them does not actually matter - it registers a precmd and a chpwd hook, and
# zsh runs every function registered on those, so it composes with the zoxide
# hook above rather than replacing it. Verified: after "z somewhere", direnv
# loads that directory's .envrc.
#
# direnv announces every load and unload on stderr, which gets noisy when z is
# how one moves around. Add DIRENV_LOG_FORMAT="" to .zshrc to silence it.
step "Hook direnv into the shell"
log "Hooking direnv into the shell..."

# shellcheck disable=SC2016 # written to .zshrc verbatim, expands there
DIRENV_HOOK='eval "$(direnv hook zsh)"'
if ! grep -qxF "$DIRENV_HOOK" ~/.zshrc; then
    echo "$DIRENV_HOOK" >> ~/.zshrc
    log "  Added the direnv hook to .zshrc."
else
    log "  The direnv hook is already in .zshrc."
fi

direnv --version

# -----------------------------------------------------------------------------
# Install Nerd Fonts
# -----------------------------------------------------------------------------
# fonts-jetbrains-mono (installed above) provides the text face; the Nerd Font
# symbol-only patch supplies the icons LazyVim and the Tmux theme render.
step "Install Nerd Fonts"
log "Installing Nerd Font symbols..."

FONT_DIR="$HOME/.local/share/fonts/SymbolsNerdFont"
mkdir -p "$FONT_DIR"
curl -fsSL -o /tmp/NerdFontsSymbolsOnly.zip https://github.com/ryanoasis/nerd-fonts/releases/latest/download/NerdFontsSymbolsOnly.zip
unzip -oq /tmp/NerdFontsSymbolsOnly.zip -d "$FONT_DIR"
rm -f /tmp/NerdFontsSymbolsOnly.zip
fc-cache -f "$HOME/.local/share/fonts" > /dev/null

log "Nerd Font symbols installed."

# -----------------------------------------------------------------------------
# Install the fd and bat shims
# -----------------------------------------------------------------------------
# Both binaries are renamed in the Ubuntu packages - fd ships as fdfind and bat
# as batcat, in each case to keep clear of an unrelated package that already
# owned the short name - while the tooling that drives them (LazyVim, fzf
# previews, the documentation of either project) looks for the short name. So
# each gets a symlink under ~/.local/bin, which is on PATH from the entry
# further down.
#
# bat itself is the syntax-highlighting, git-aware pager cat never was. It is
# deliberately NOT aliased over cat: only interactive zsh would see such an
# alias, so a script piping cat and a prompt running it would behave
# differently, and that is a poor trade for six saved keystrokes.
step "Install the fd and bat shims"
mkdir -p "$HOME/.local/bin"
for shim_entry in fd:fdfind bat:batcat; do
    shim_name="${shim_entry%%:*}"
    shim_target="${shim_entry#*:}"
    if [ -e "$HOME/.local/bin/$shim_name" ]; then
        log "$shim_name shim already present. Skipping."
        continue
    fi
    log "Linking $shim_target as $shim_name in ~/.local/bin..."
    ln -s "$(which "$shim_target")" "$HOME/.local/bin/$shim_name"
done

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
step "Install Tmux Plugin Manager"
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
step "Install the hardware-specific packages"
VIRT="$(systemd-detect-virt || true)"
case "$VIRT" in
    vmware)
        log "VMware guest detected - installing open-vm-tools-desktop..."
        sudo apt install -y open-vm-tools-desktop
        ;;
    none)
        log "Bare metal detected - installing recommended proprietary drivers..."
        sudo ubuntu-drivers install || log "No additional drivers were installed."
        # btop for the graphics card - per-process GPU and VRAM use. Here
        # rather than in the package list above because it needs a real GPU to
        # report on: in a VM it opens on an empty screen.
        sudo apt install -y nvtop
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
step "Remove the Firefox snap (opt-in only)"
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
# Not a question: the changes above only take effect at the next login, and
# the next script depends on them. Enter reboots; Ctrl-C is the way out for
# whoever wants to reboot later - the completion marker is written already.
step "Reboot after installation"
log "The machine has to reboot for the changes to take effect."
read -r -p "Press Enter to reboot..."
echo "Rebooting..."
exec sudo /sbin/reboot now
