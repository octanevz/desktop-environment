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

A set of scripts intended to be run sequentially on a fresh Ubuntu 26.04 LTS installation. Each script handles a specific layer of the setup:

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
| `update-all.sh` | `update-all` | Runs `update-sys.sh` (which also covers the .NET SDK, since it comes from the archive), then updates global npm packages, csharp-ls, Claude Code, herdr, the Oh My Zsh plugins, and lazygit |

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
