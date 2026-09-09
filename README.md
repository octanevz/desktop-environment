# Desktop Environment Setup Scripts

> **Important:** These scripts are tailored to the author's personal setup and preferences. Do not run them blindly on your system. Review every script carefully before execution. If you find this useful, fork the repository and adapt the scripts to your own needs rather than using them as-is.

## Purpose

Automation scripts for setting up desktop environments from scratch, primarily for software development. The goal is to go from a fresh OS install to a fully configured development workstation with minimal manual intervention.

## Available Setups

### Debian 13 (Trixie) - Development

Location: `linux/debian/13-trixie-dev/`

A set of scripts intended to be run sequentially on a fresh Debian 13 (Trixie) installation. Each script handles a specific layer of the setup:

| Script | What it does |
|--------|-------------|
| `setup_0_packages.sh` | Updates the OS, installs essential packages (curl, git, gpg, mesa-utils, etc.), installs Oh My Zsh with autosuggestions and syntax highlighting, sets Zsh as the default shell |
| `setup_1_devtools.sh` | Installs Docker Engine, Google Chrome, Visual Studio Code, Node.js 24 (via nvm), npm packages (Angular CLI, Codex CLI, markdown-tree-parser), .NET 10 LTS, Claude Code, and registers `upd`/`updall` shell aliases |
| `setup_2_claude_code_plugins.sh` | Installs Claude Code plugins (superpowers, context7, feature-dev, frontend-design, hookify, and others) |
| `setup_3_jetbrains_toolbox.sh` | Installs JetBrains Toolbox |
| `setup_4_docker_images.sh` | Pulls Docker images: PostgreSQL 18, Jupyter SciPy Notebook, Jupyter PyTorch Notebook |

Two maintenance scripts are also included and registered as shell aliases during setup:

| Script | Alias | What it does |
|--------|-------|-------------|
| `upd.sh` | `upd` | Updates and cleans up Debian packages |
| `updall.sh` | `updall` | Updates Debian packages, global npm packages, and Claude Code |

### Running the scripts

Assuming the repo has been cloned to `~/github/octanevz/desktop-environment`:

1. Navigate to the setup directory and make the scripts executable:
   ```bash
   cd ~/github/octanevz/desktop-environment/linux/debian/13-trixie-dev
   chmod +x *.sh
   ```
2. Install packages and set up the shell:
   ```bash
   ./setup_0_packages.sh # reboot when prompted
   ```
3. After reboot, open your terminal and navigate back to the setup directory:
   ```bash
   cd ~/github/octanevz/desktop-environment/linux/debian/13-trixie-dev
   ```
4. Install applications and dev tools:
   ```bash
   ./setup_1_devtools.sh # reboot when prompted
   ```
5. After reboot, open your terminal and navigate back to the setup directory. Then run any of the optional scripts as needed:
   ```bash
   cd ~/github/octanevz/desktop-environment/linux/debian/13-trixie-dev
   ./setup_2_claude_code_plugins.sh # optional
   ./setup_3_jetbrains_toolbox.sh # optional
   ./setup_4_docker_images.sh # optional
   ```

### Ubuntu 26.04 - Development

Location: `linux/ubuntu/2604-dev/`

The Ubuntu counterpart of the Debian setup above, intended to be run sequentially on a fresh Ubuntu 26.04 LTS installation. The first five scripts follow the Debian layering, adapted to Ubuntu (Ubuntu Docker repository and codename, `universe` component, snap handling, `ubuntu-drivers`). Four more scripts add a source-built Alacritty, LazyVim, two GNOME Shell extensions and the configuration files kept in `config/`:

| Script | What it does |
|--------|-------------|
| `setup_0_packages.sh` | Enables `universe` and `multiverse`, updates the OS, installs essential packages (curl, git, gpg, mesa-utils, GIMP, Extension Manager, etc.), installs Oh My Zsh with autosuggestions and syntax highlighting, sets Zsh as the default shell, installs everything LazyVim needs (Neovim stable, ripgrep, fd-find, fzf, build-essential, tree-sitter-cli, lazygit, xclip/wl-clipboard, JetBrains Mono + Nerd Font symbols, python3/venv/pip), installs the runtime libraries Alacritty links against, sets an English interface with German formats, installs the Microsoft core fonts, installs Tmux Plugin Manager, and installs the VMware guest tools in a VMware VM or proprietary drivers on bare metal |
| `setup_1_devtools.sh` | Installs Docker Engine, Google Chrome, Visual Studio Code, Orca ADE, GitHub CLI, Node.js 24 (via nvm), npm packages (Codex CLI, OpenCode, markdown-tree-parser, Prettier, markdownlint-cli2, Pyright and the TypeScript language server), .NET 10 LTS from the Ubuntu archive plus csharp-ls, Claude Code, herdr (with its Zsh completion), and registers `update-sys`/`update-all` shell aliases |
| `setup_2_claude_code_plugins.sh` | Installs Claude Code plugins from the official marketplace (context7, feature-dev, frontend-design, hookify, and others), plus `codex-debate` from the `octanevz` marketplace. The three `*-lsp` plugins use the language servers `setup_1` installs |
| `setup_3_jetbrains_toolbox.sh` | Installs JetBrains Toolbox |
| `setup_4_docker_images.sh` | Pulls Docker images: PostgreSQL 18, Jupyter SciPy Notebook, Jupyter PyTorch Notebook, and the `ubuntu:26.04` image `setup_5` builds in, removing the previous version of each |
| `setup_5_alacritty.sh` | Builds Alacritty from source in an `ubuntu:26.04` Docker container and installs the binary, terminfo, desktop entry, icon, man pages and Zsh completion on the host. Needs `setup_0` (runtime libraries) and `setup_1` (Docker) |
| `setup_6_lazyvim.sh` | Installs the LazyVim starter into `~/.config/nvim`, enables the `lang.json` and `lang.markdown` extras, sets `spelllang` to `en_us`, and installs the plugins headlessly. Needs `setup_0` (prerequisites) |
| `setup_7_gnome_extensions.sh` | Installs the Caffeine and Tiling Shell GNOME Shell extensions from extensions.gnome.org, matched to the running GNOME Shell version, enables them, and loads their settings from `config/dconf/` with `dconf load`. Needs `setup_0` (prerequisites) |
| `setup_8_configs.sh` | Installs the configuration files from `config/`: `.tmux.conf` (plus the TPM plugins), the Alacritty config and the theme repository it imports, the herdr config, and the shared `file-picker` helper, and pins the installed applications to the GNOME dock. Backs up anything it replaces |

Two maintenance scripts are also included and registered as shell aliases during setup:

| Script | Alias | What it does |
|--------|-------|-------------|
| `update-sys.sh` | `update-sys` | Updates and cleans up Ubuntu packages and snaps |
| `update-all.sh` | `update-all` | Runs `update-sys.sh` (which also covers the .NET SDK, since it comes from the archive), then updates global npm packages, csharp-ls, Claude Code, herdr, the Oh My Zsh plugins, and lazygit. Neovim and Alacritty are deliberately left out - see below |

The notes that follow are grouped by script.

#### Packages (`setup_0_packages.sh`)

`setup_0_packages.sh` installs only LazyVim's prerequisites; LazyVim itself is installed by `setup_6_lazyvim.sh`. Neovim and lazygit are installed from their upstream releases instead of the Ubuntu archive, because the archive versions are frozen for the lifetime of the release and go stale before LazyVim's requirements do. Neither has a self-update, and apt does not know about them: `update-all` refreshes lazygit (only when the installed version differs from the latest release), while Neovim is deliberately left pinned, since an unexpected Neovim bump can break LazyVim plugins - re-run `setup_0_packages.sh` when you want it moved.

The archive `alacritty` package is not installed at all: `universe` ships 0.16.1 while upstream stable is v0.17.0, and `setup_5_alacritty.sh` builds the current release from source, so installing 0.16.1 only for the build to supersede it would be pointless. Ubuntu ships GNOME Terminal, so the machine is never without a terminal in the meantime. What `setup_0_packages.sh` does install are the shared libraries the Alacritty binary links against at run time - see the Alacritty notes below for why that split exists.

`setup_0_packages.sh` installs `ttf-mscorefonts-installer` from `multiverse`, which requires agreeing to the Microsoft core fonts EULA. The script **pre-accepts that EULA** through debconf so the run stays unattended - if you do not want to agree to it, delete that section. The package downloads the fonts from a SourceForge mirror at install time, so it needs network beyond the apt mirrors; a failure there is reported and does not abort the rest of the setup.

Ubuntu Desktop ships Firefox as a snap. Since Google Chrome is installed by `setup_1_devtools.sh`, `setup_0_packages.sh` can remove it, but only when asked explicitly (it also deletes the profile):

```bash
REMOVE_FIREFOX_SNAP=1 ./setup_0_packages.sh
```

##### Locale

`setup_0_packages.sh` sets an English interface with German formats, the split GNOME's Region & Language panel calls *Language* and *Formats*. `LANG` and `LANGUAGE` stay `en_US.UTF-8`, so menus, messages and man pages are English, while `LC_TIME`, `LC_NUMERIC`, `LC_MONETARY`, `LC_PAPER`, `LC_MEASUREMENT`, `LC_ADDRESS` and `LC_TELEPHONE` become `de_DE.UTF-8` - German dates, 24-hour clock, decimal commas, A4 and Monday as the first day of the week. Change `UI_LOCALE` and `FORMATS_LOCALE` at the top of the script for a different pair.

It is set in two places, because one is not enough. `update-locale` writes `/etc/default/locale`, which PAM applies to every login shell, SSH session and cron job; GNOME ignores that file for formats and exports the same categories from its own setting, so `org.gnome.system.locale region` is set as well. Both come from the same two variables, so they cannot drift apart. Note that the dconf path behind that schema is the legacy `/system/locale/`, not `/org/gnome/system/locale/`.

Both locales are generated first, `en_US.UTF-8` included: `update-locale` validates every value it is given and rejects the whole call if one is missing, so an install done in another language would otherwise fail here. One consequence is worth knowing about - `LC_NUMERIC` makes the comma the decimal separator for everything in the session, so `printf '%.2f' 1234.56` fails and tools parsing C-format numbers can misread them. Drop `LC_NUMERIC` from `FORMAT_CATEGORIES` if that gets in the way.

#### Dev tools (`setup_1_devtools.sh`)

Orca ADE is installed from the `.deb` attached to the latest [stablyai/orca](https://github.com/stablyai/orca) release, resolved through the GitHub API since those releases have no stable "latest" URL. It is the one install here with no apt repository behind it, so `update-all` does not update it - it does not need to, because the app self-updates from the same GitHub releases via its own Check for Updates. Re-running `setup_1_devtools.sh` only seeds the initial install. Its CLI is linked into `~/.local/bin` as `orca-ide`, never as plain `orca`, which on Debian/Ubuntu is the GNOME screen reader.

herdr is installed from its official installer at <https://herdr.dev>. Like Orca ADE it is not a package - a single static binary in `~/.local/bin`, which `setup_0_packages.sh` already puts on PATH - but unlike Orca ADE it updates itself, so `update-all` runs `herdr update`.

#### Docker images (`setup_4_docker_images.sh`)

All four images `setup_4_docker_images.sh` pulls are floating tags, and a pull that moves a tag leaves the image it replaced behind untagged. The script therefore removes the previous version of each image it pulls, identified by remembering its ID across the pull - it never runs a blanket `docker image prune`, so untagged images from unrelated work are left alone, as is any old version that still carries another tag.

#### Alacritty (`setup_5_alacritty.sh`)

There are no official Alacritty binaries for Linux, and the archive package is stale (see above), so `setup_5_alacritty.sh` builds it from source. It does so inside an `ubuntu:26.04` container so the ~1.5 GB Rust toolchain never touches the host, and so the build glibc matches the target exactly.

The dependencies are deliberately split: the shared libraries the binary links against at run time are installed by `setup_0_packages.sh` on the host, while the build dependencies - the Rust toolchain and the `-dev` packages - exist only inside the build container and are never installed on the host. `setup_5_alacritty.sh` performs no apt installs on the host at all: it verifies the runtime libraries - and the `desktop-file-install` helper it needs - are present, and exits with an error telling you to run `setup_0_packages.sh` first if any are missing. It also needs Docker from `setup_1_devtools.sh`, so run it after both.

To update Alacritty, bump `ALACRITTY_VERSION` at the top of `setup_5_alacritty.sh` to the new tag and re-run it: the script re-points the clone at that tag and rebuilds only when the installed version differs. Nothing else updates it - it has no apt repository, and it is deliberately left out of `update-all` so that routine updates stay fast. Rebuild the same version anyway with `FORCE=1 ./setup_5_alacritty.sh` (or `--force`), and build the development branch with `ALACRITTY_VERSION=master ./setup_5_alacritty.sh`.

#### LazyVim (`setup_6_lazyvim.sh`)

`setup_6_lazyvim.sh` installs LazyVim itself; it installs none of the prerequisites, only checks that `setup_0_packages.sh` put them there. Everything is left at LazyVim defaults except two things: the `lang.json` and `lang.markdown` extras are enabled (a plugin selection, without which the JSON and Markdown tooling is not installed at all), and `spelllang` is set to `en_us` instead of the default `en`. No `lazy-lock.json` is carried over, so a fresh machine resolves current plugin versions. An existing `~/.config/nvim` is never clobbered - the script reports it and stops, and `--force` moves all four Neovim directories aside to timestamped backups first. The plugins are installed at the end by running Neovim headlessly (`Lazy! sync`), so the first interactive start is not spent cloning; the treesitter parsers and Mason tools still download on that first start, since those plugins do not load during a headless sync.

#### GNOME extensions (`setup_7_gnome_extensions.sh`)

`setup_7_gnome_extensions.sh` installs Caffeine and Tiling Shell. Neither is packaged in Ubuntu 26.04, so both come from extensions.gnome.org. Extension builds are per GNOME Shell version, so the script detects the running shell version and installs the release published for it, refusing to install anything else rather than falling back to an incompatible build. Their settings are deployed too, as `dconf` dumps in `config/dconf/`, loaded with `dconf load`. Whatever is currently in `dconf` is dumped to a backup under `~/.local/state/gnome-extension-settings/` before anything is written. A load is skipped only when the live settings already equal the dump, which is rarely the case for Tiling Shell - it rewrites some of the dumped keys itself - so expect a backup and a reload on most re-runs. To capture your own, configure the extensions with Extension Manager (`setup_0_packages.sh` installs it) and dump them back into the repo:

```bash
dconf dump /org/gnome/shell/extensions/caffeine/ > config/dconf/caffeine.ini
dconf dump /org/gnome/shell/extensions/tilingshell/ > config/dconf/tiling-shell.ini
```

One key in `tiling-shell.ini` is written by the extension rather than chosen: `last-version-name-installed` suppresses its "what's new" screen and is carried over as dumped. `overridden-settings`, which the extension writes to record the GNOME keybindings it replaced so it can restore them when disabled, is deliberately left out of the dump - it is per-machine undo state, and a pre-seeded copy would be restored in place of the machine's own bindings. Strip it again after re-dumping. The extensions do not load until you log out and log back in; on Wayland, which Ubuntu 26.04 uses by default, restarting the shell is not an option.

#### Configuration files (`setup_8_configs.sh`)

`setup_8_configs.sh` deploys files from the repository rather than installing software: `config/` holds the tmux, Alacritty and herdr configuration and the `file-picker` helper (`config/dconf/` belongs to `setup_7_gnome_extensions.sh` instead). It never overwrites in place - a file that differs is copied to `<name>.bak-<timestamp>` first, and one that is already identical is left alone, so re-running does not pile up backups. It also fills a gap: `setup_0_packages.sh` installs tmux and the Tmux Plugin Manager, but without a `.tmux.conf` TPM had nothing to read and no plugins were ever declared. Finally it sets the GNOME dock favourites to the applications the scripts install (Files, Alacritty, VS Code, Orca ADE, JetBrains Toolbox, Chrome, GIMP, Settings), replacing Ubuntu's default set; only applications whose `.desktop` file exists are pinned, so re-run it after an optional script - or after the first JetBrains Toolbox launch, which is when Toolbox writes its `.desktop` file - to add the missing icon. The list is the `DOCK_FAVORITES` array at the top of the section.

`file-picker` is bound to `prefix`+`Ctrl`+`f` in both tmux and herdr. It is one script that branches only on how it sends the chosen path back - `tmux send-keys` or `herdr pane send-text` - and prints the path to stdout when run outside either.

### Running the scripts

Assuming the repo has been cloned to `~/github/octanevz/desktop-environment`:

1. Navigate to the setup directory and make the scripts executable:
   ```bash
   cd ~/github/octanevz/desktop-environment/linux/ubuntu/2604-dev
   chmod +x *.sh
   ```
2. Install packages and set up the shell:
   ```bash
   ./setup_0_packages.sh # reboot when prompted
   ```
3. After reboot, open your terminal and navigate back to the setup directory:
   ```bash
   cd ~/github/octanevz/desktop-environment/linux/ubuntu/2604-dev
   ```
4. Install applications and dev tools:
   ```bash
   ./setup_1_devtools.sh # reboot when prompted
   ```
5. After reboot, open your terminal and navigate back to the setup directory. Then run any of the optional scripts as needed:
   ```bash
   cd ~/github/octanevz/desktop-environment/linux/ubuntu/2604-dev
   ./setup_2_claude_code_plugins.sh # optional, needs setup_1 (Codex CLI, language servers)
   ./setup_3_jetbrains_toolbox.sh # optional
   ./setup_4_docker_images.sh # optional, needs setup_1 (Docker)
   ./setup_5_alacritty.sh # optional, needs setup_0 (libraries) and setup_1 (Docker)
   ./setup_6_lazyvim.sh # optional, needs setup_0 (prerequisites)
   ./setup_7_gnome_extensions.sh # optional, needs setup_0 (prerequisites)
   ./setup_8_configs.sh # optional, needs setup_0 and setup_1
   ```

## Repository Structure

```
linux/
  debian/
    13-trixie-dev/ # Debian 13 Trixie development setup
      setup_0_packages.sh
      setup_1_devtools.sh
      setup_2_claude_code_plugins.sh
      setup_3_jetbrains_toolbox.sh
      setup_4_docker_images.sh
      upd.sh
      updall.sh
  ubuntu/
    2604-dev/ # Ubuntu 26.04 LTS development setup
      setup_0_packages.sh
      setup_1_devtools.sh
      setup_2_claude_code_plugins.sh
      setup_3_jetbrains_toolbox.sh
      setup_4_docker_images.sh
      setup_5_alacritty.sh
      setup_6_lazyvim.sh
      setup_7_gnome_extensions.sh
      setup_8_configs.sh
      config/
        tmux.conf # deployed by setup_8
        alacritty/alacritty.toml
        herdr/config.toml
        bin/file-picker
        dconf/ # loaded by setup_7
          caffeine.ini
          tiling-shell.ini
      update-sys.sh
      update-all.sh
```

## License

BSD 3-Clause. See [LICENSE](LICENSE) for details.
