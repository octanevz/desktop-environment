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

A set of scripts intended to be run sequentially on a fresh Ubuntu 26.04 LTS installation. Each script handles a specific layer of the setup. The numbered scripts run once: each records its completion under `~/.local/state/desktop-environment/`, exits immediately when run again (pass `--force` to override), and refuses to run before every lower-numbered script has completed. `setup-agents.sh` and the maintenance scripts can be run at any time.

| Script | What it does |
|--------|-------------|
| `setup-00-packages.sh` | Enables `universe`, updates the OS, installs essential packages (curl, git, git-lfs, git-absorb, gpg, jq, rsync, postgresql-client, mesa-utils, tmux, GIMP, Extension Manager, etc.) and the runtime libraries Alacritty links against, sets an English interface with German formats (installing the matching language packs), installs Oh My Zsh with autosuggestions and syntax highlighting, sets Zsh as the default shell, aliases `l`, `lf` (files only) and `ld` (directories only) to `eza`, sets up `atuin` as the Ctrl-R shell history (importing the existing one), sets up `zoxide` as the `z` directory jumper, binds the `fzf` keys (Ctrl-T, Alt-C) with `fd`/`bat`/`eza` previews, hooks in `direnv`, shims `fdfind`/`batcat` as `fd`/`bat`, installs the LazyVim prerequisites (ripgrep, fd-find, fzf, build-essential, tree-sitter-cli, xclip/wl-clipboard, JetBrains Mono + Nerd Font symbols, python3/venv/pip), installs Tmux Plugin Manager, installs the VMware guest tools in a VMware VM or proprietary drivers on bare metal, and optionally removes the Firefox snap (`REMOVE_FIREFOX_SNAP=1`) |
| `setup-01-devtools.sh` | Installs Docker Engine, Neovim (upstream stable), lazygit, lazydocker, Google Chrome, Visual Studio Code, Orca ADE, GitHub CLI, Node.js 24 (via nvm), npm packages (Codex CLI, OpenCode, markdown-tree-parser, Prettier, markdownlint-cli2, Pyright and the TypeScript language server), .NET 10 LTS via Microsoft's `dotnet-install.sh` (so the newest SDK is available the day it is published) plus csharp-ls, uv (with `uvx` and Zsh completions) and Ruff as a uv tool, Claude Code, herdr (with its Zsh completion), and registers `update-sys`/`update-all` shell aliases |
| `setup-02-jetbrains-toolbox.sh` | Installs JetBrains Toolbox |
| `setup-03-docker-images.sh` | Pulls Docker images: PostgreSQL 18, Jupyter SciPy Notebook, Jupyter PyTorch Notebook, and the `ubuntu:26.04` image `setup-04` builds in, removing the previous version of each |
| `setup-04-alacritty.sh` | Builds Alacritty from source in an `ubuntu:26.04` Docker container and installs the binary, terminfo, desktop entry, icon, man pages and Zsh completion on the host. Needs `setup-00` (runtime libraries) and `setup-01` (Docker) |
| `setup-05-lazyvim.sh` | Installs the LazyVim starter into `~/.config/nvim`, enables the `lang.json` and `lang.markdown` extras plus the recommended ones (`ai.copilot`, `coding.yanky`, `editor.dial`, `editor.inc-rename`, `editor.snacks_explorer`, `editor.snacks_picker`, `test.core`, `util.dot`, `util.mini-hipatterns`), sets `spelllang` to `en_us`, and installs the plugins headlessly. Needs `setup-00` (prerequisites) and `setup-01` (Neovim, lazygit, Node.js). Run `:Copilot auth` once inside Neovim to sign in to Copilot |
| `setup-06-gnome-extensions.sh` | Installs the Caffeine and Tiling Shell GNOME Shell extensions from extensions.gnome.org, matched to the running GNOME Shell version, enables them, and loads their settings from `config/dconf/` with `dconf load`. Needs `setup-00` (prerequisites) |
| `setup-07-configs.sh` | Installs the configuration files from `config/`: `.tmux.conf` (plus the TPM plugins), the Alacritty config and the theme repository it imports, the herdr config, and the shared `file-picker` helper, and pins the installed applications to the GNOME dock. Backs up anything it replaces |
| `setup-08-git.sh` | Configures Git. **Stops before writing anything when `~/.ssh` holds no private key** (pass `ALLOW_NO_SSH_KEYS=1` for a machine that only uses HTTPS remotes). Otherwise: **asks for** the name and email (offering whatever is already configured, or set `GIT_USER_NAME`/`GIT_USER_EMAIL` to skip the questions), sets the behaviour this setup assumes (rebase on pull, prune on fetch, an upstream on the first push, `rerere`, the `histogram` diff and the `zdiff3` conflict style), points the pager at delta, registers the Git LFS filters, registers the GitHub CLI as the credential helper for HTTPS remotes, and lists the SSH keys in `~/.ssh` to offer `ssh-add` for each. It does **not** configure commit signing, and installs no global gitignore. Every key is written with `git config --global`, so settings other tools wrote into `~/.gitconfig` survive. It records itself as complete only when nothing was left undone, so a step blocked by something fixable (an unauthenticated `gh`) is picked up by a plain re-run without `--force`. Needs `setup-00` (git, git-delta, git-lfs) and `setup-01` (Neovim, the GitHub CLI) |
| `setup-agents.sh` | Installs Claude Code plugins from the official marketplace (context7, feature-dev, frontend-design, hookify, and others), plus `codex-debate` from the `octanevz` marketplace. The three `*-lsp` plugins use the language servers `setup-01` installs. Also installs the Orca ADE skills (computer-use, orca-cli, orchestration) and find-skills for Claude Code, Codex and OpenCode at once via `npx skills`. Not part of the numbered sequence; checks that Claude Code and the Codex CLI are logged in first |

Two maintenance scripts are also included and registered as shell aliases during setup:

| Script | Alias | What it does |
|--------|-------|-------------|
| `update-sys.sh` | `update-sys` | Updates and cleans up Ubuntu packages and snaps |
| `update-all.sh` | `update-all` | Runs `update-sys.sh`, then updates the .NET SDK (pruning older SDKs and runtimes), global npm packages, csharp-ls, uv and its tools (Ruff), Claude Code, the agent skills, herdr, the Oh My Zsh plugins, lazygit, and lazydocker |

### Running the scripts

Assuming the repo has been cloned to `~/github/octanevz/desktop-environment`:

1. Navigate to the setup directory and make the scripts executable:
   ```bash
   cd ~/github/octanevz/desktop-environment/linux/ubuntu/2604-dev
   chmod +x *.sh
   ```
2. Install packages and set up the shell:
   ```bash
   ./setup-00-packages.sh # reboot when prompted
   ```
3. After reboot, open your terminal and navigate back to the setup directory:
   ```bash
   cd ~/github/octanevz/desktop-environment/linux/ubuntu/2604-dev
   ```
4. Install applications and dev tools:
   ```bash
   ./setup-01-devtools.sh # reboot when prompted
   ```
5. After reboot, open your terminal and navigate back to the setup directory. Then run the remaining scripts in order:
   ```bash
   cd ~/github/octanevz/desktop-environment/linux/ubuntu/2604-dev
   ./setup-02-jetbrains-toolbox.sh
   ./setup-03-docker-images.sh
   ./setup-04-alacritty.sh
   ./setup-05-lazyvim.sh
   ./setup-06-gnome-extensions.sh
   ./setup-07-configs.sh
   ./setup-08-git.sh # needs your SSH keys in ~/.ssh; asks for your name and email
   ./setup-agents.sh # any time after setup-01 and the Claude Code and Codex logins
   ```

## Repository Structure

```
cheatsheet.html # Shell/Docker/Git/Tmux/Neovim/GNOME cheatsheet
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
      config/
        alacritty/alacritty.toml # deployed by setup-07
        bin/file-picker # deployed by setup-07
        dconf/ # loaded by setup-06
          caffeine.ini
          tiling-shell.ini
        herdr/config.toml # deployed by setup-07
        tmux.conf # deployed by setup-07
      common.sh # sourced by the numbered scripts
      setup-00-packages.sh
      setup-01-devtools.sh
      setup-02-jetbrains-toolbox.sh
      setup-03-docker-images.sh
      setup-04-alacritty.sh
      setup-05-lazyvim.sh
      setup-06-gnome-extensions.sh
      setup-07-configs.sh
      setup-08-git.sh
      setup-agents.sh
      update-all.sh
      update-sys.sh
```

## License

BSD 3-Clause. See [LICENSE](LICENSE) for details.
