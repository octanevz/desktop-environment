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
| `setup-00-packages.sh` | Enables `universe`, updates the OS, installs essential packages (curl, git, git-lfs, git-absorb, gpg, jq, rsync, postgresql-client, mesa-utils, tmux, GIMP, Extension Manager, etc.) and the runtime libraries Alacritty links against, sets an English interface with German formats (installing the matching language packs), installs Oh My Zsh with autosuggestions and syntax highlighting, sets Zsh as the default shell, aliases `l`, `lf` (files only) and `ld` (directories only) to `eza`, aliases `cls` to `clear`, sets up `atuin` as the Ctrl-R shell history (importing the existing one), sets up `zoxide` as the `z` directory jumper, binds the `fzf` keys (Ctrl-T, Alt-C) with `fd`/`bat`/`eza` previews, hooks in `direnv`, installs the terminal tools (`tealdeer`, `duf`, `ncdu`, `entr`, `glow`, `just`, `hyperfine`, `imagemagick`, `ffmpeg`, `sqlite3`, `pre-commit`, `gitleaks`, and `nvtop` on bare metal), shims `fdfind`/`batcat` as `fd`/`bat`, installs the LazyVim prerequisites (ripgrep, fd-find, fzf, build-essential, tree-sitter-cli, xclip/wl-clipboard, JetBrains Mono + Nerd Font symbols, python3/venv/pip), installs MesloLGM Nerd Font Mono as the terminal font, installs Tmux Plugin Manager, installs the VMware guest tools in a VMware VM or proprietary drivers on bare metal, and optionally removes the Firefox snap (`REMOVE_FIREFOX_SNAP=1`) |
| `setup-01-devtools.sh` | Installs Docker Engine, Neovim (upstream stable), lazygit, lazydocker, dive, yq (mikefarah's Go one, not the archive's Python jq wrapper), Google Chrome, Visual Studio Code, Orca ADE, JetBrains Toolbox, GitHub CLI, Node.js 24 (via nvm), npm packages (Codex CLI, OpenCode, markdown-tree-parser, Prettier, markdownlint-cli2, Pyright and the TypeScript language server), .NET 10 LTS via Microsoft's `dotnet-install.sh` (so the newest SDK is available the day it is published, telemetry opted out) plus csharp-ls, uv (with `uvx` and Zsh completions) and Ruff as a uv tool, Claude Code, herdr (with its Zsh completion), and registers `update-sys`/`update-all` shell aliases |
| `setup-02-docker-images.sh` | Pulls Docker images: PostgreSQL 18, Jupyter SciPy Notebook, Jupyter PyTorch Notebook, and the `ubuntu:26.04` image `setup-03-alacritty.sh` builds in, removing the previous version of each |
| `setup-03-alacritty.sh` | Builds Alacritty from source in an `ubuntu:26.04` Docker container and installs the binary, terminfo, desktop entry, icon, man pages and Zsh completion on the host. Needs `setup-00-packages.sh` (runtime libraries) and `setup-01-devtools.sh` (Docker) |
| `setup-04-lazyvim.sh` | Installs the LazyVim starter into `~/.config/nvim`, enables the `lang.json` and `lang.markdown` extras plus the recommended ones (`ai.copilot`, `coding.yanky`, `editor.dial`, `editor.inc-rename`, `editor.snacks_explorer`, `editor.snacks_picker`, `test.core`, `util.dot`, `util.mini-hipatterns`), sets `spelllang` to `en_us`, and installs the plugins headlessly, with a lazy.nvim git timeout and headless concurrency that let the sync finish on a slow link; the treesitter parsers, Mason tools and language servers are downloaded on the first start. Needs `setup-00-packages.sh` (prerequisites) and `setup-01-devtools.sh` (Neovim, lazygit, Node.js). Run `:Copilot auth` once inside Neovim to sign in to Copilot |
| `setup-05-gnome-extensions.sh` | Installs the Caffeine and Tiling Shell GNOME Shell extensions from extensions.gnome.org, matched to the running GNOME Shell version, enables them, and loads their settings from `config/dconf/` with `dconf load`. Needs `setup-00-packages.sh` (prerequisites). Records itself as complete only when every dconf write went through, so a run without a session bus (over SSH) is retried by a plain re-run. The extensions load at the next login, which `setup-06-configs.sh` ends with |
| `setup-06-configs.sh` | Installs the configuration files from `config/`: `.tmux.conf` (plus the TPM plugins), the Alacritty config and the theme repository it imports, the herdr config, the shared `file-picker` helper, and the `xdg-terminals.list` that makes Alacritty the default terminal (Ctrl+Alt+T, "Open in Terminal"); applies the GNOME desktop settings from `config/dconf/gnome-settings.ini` (theme, wallpaper, keyboard layout, dock, power, Text Editor and Ptyxis preferences) key by key, and pins the installed applications to the GNOME dock. Backs up anything it replaces, the previous value of every changed dconf key included. Records itself as complete only when nothing was left undone (a dconf write without a session bus, a failed TPM fetch), so a plain re-run picks those up. Needs `setup-03-alacritty.sh` as well. Ends by logging out on Enter, so the shell loads the extensions from `setup-05-gnome-extensions.sh` at the next login |
| `setup-07-git.sh` | Configures Git. **Asks for** the name and email (offering whatever is already configured, or set `GIT_USER_NAME`/`GIT_USER_EMAIL` to skip the questions), sets the behaviour this setup assumes (rebase on pull, prune on fetch, an upstream on the first push, `rerere`, the `histogram` diff and the `zdiff3` conflict style), points the pager at delta, registers the Git LFS filters, and registers the GitHub CLI as the credential helper for HTTPS remotes. It does **not** touch SSH (keys are restored and added to the agent by hand), does **not** configure commit signing, and installs no global gitignore. Every key is written with `git config --global`, so settings other tools wrote into `~/.gitconfig` survive. It records itself as complete only when nothing was left undone, so a step blocked by something fixable (an unauthenticated `gh`) is picked up by a plain re-run without `--force`. Needs `setup-00-packages.sh` (git, git-delta, git-lfs) and `setup-01-devtools.sh` (Neovim, the GitHub CLI) |
| `setup-agents.sh` | Installs Claude Code plugins from the official marketplace (context7, feature-dev, frontend-design, hookify, and others), plus `codex-debate` from the `octanevz` marketplace. The three `*-lsp` plugins use the language servers `setup-01-devtools.sh` installs. Also installs the Orca ADE skills (computer-use, orca-cli, orchestration) and find-skills for Claude Code, Codex and OpenCode at once via `npx skills`. Not part of the numbered sequence; checks that Claude Code and the Codex CLI are logged in first |

Two maintenance scripts are also included and registered as shell aliases during setup:

| Script | Alias | What it does |
|--------|-------|-------------|
| `update-sys.sh` | `update-sys` | Updates and cleans up Ubuntu packages and snaps |
| `update-all.sh` | `update-all` | Runs `update-sys.sh`, then updates the .NET SDK (pruning older SDKs and runtimes), global npm packages, csharp-ls, uv and its tools (Ruff), Claude Code, the agent skills, herdr, the Oh My Zsh plugins, lazygit, lazydocker, dive, and yq, regenerating the Zsh completions of the tools it moved |

### Running the scripts

Assuming the repo has been cloned to `~/github/octanevz/desktop-environment`. Each block below is one command chain to paste into a terminal; the chain stops at the first script that fails, and the reboots and the log out are where a fresh terminal is needed anyway.

1. Install packages and set up the shell:

   ```bash
   cd ~/github/octanevz/desktop-environment/linux/ubuntu/2604-dev &&
     ./setup-00-packages.sh # reboot when prompted
   ```

2. After the reboot, open a terminal and install the applications and dev tools:

   ```bash
   cd ~/github/octanevz/desktop-environment/linux/ubuntu/2604-dev &&
     ./setup-01-devtools.sh # reboot when prompted
   ```

3. After the reboot, open a terminal and run the remaining scripts up to the log out:

   ```bash
   cd ~/github/octanevz/desktop-environment/linux/ubuntu/2604-dev &&
     ./setup-02-docker-images.sh &&
     ./setup-03-alacritty.sh &&
     ./setup-04-lazyvim.sh &&
     ./setup-05-gnome-extensions.sh &&
     ./setup-06-configs.sh # logs out when prompted
   ```

4. After logging back in, open a terminal and configure Git:

   ```bash
   cd ~/github/octanevz/desktop-environment/linux/ubuntu/2604-dev &&
     ./setup-07-git.sh # asks for your name and email
   ```

5. Log in to Claude Code and the Codex CLI, then install the agent plugins and skills (any time after step 2):

   ```bash
   cd ~/github/octanevz/desktop-environment/linux/ubuntu/2604-dev &&
     ./setup-agents.sh
   ```

## Repository Structure

```text
.editorconfig            # Shell formatting style, read by shfmt
.markdownlint-cli2.yaml  # Markdown rules this README turns off
.pre-commit-config.yaml  # Commit hooks: shfmt, shellcheck, markdownlint,
                         #   prettier, ruff, gitleaks
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
        alacritty/alacritty.toml # deployed by setup-06-configs.sh
        bin/file-picker # deployed by setup-06-configs.sh
        dconf/
          caffeine.ini # loaded by setup-05-gnome-extensions.sh
          gnome-settings.ini # loaded by setup-06-configs.sh
          tiling-shell.ini # loaded by setup-05-gnome-extensions.sh
        herdr/config.toml # deployed by setup-06-configs.sh
        tmux.conf # deployed by setup-06-configs.sh
        xdg-terminals.list # deployed by setup-06-configs.sh
      common.sh # sourced by the numbered scripts
      setup-00-packages.sh
      setup-01-devtools.sh
      setup-02-docker-images.sh
      setup-03-alacritty.sh
      setup-04-lazyvim.sh
      setup-05-gnome-extensions.sh
      setup-06-configs.sh
      setup-07-git.sh
      setup-agents.sh
      update-all.sh
      update-sys.sh
```

## Development

The hooks in `.pre-commit-config.yaml` run the formatters and linters this
setup already installs - shfmt, shellcheck, markdownlint-cli2, Prettier, Ruff
and gitleaks. They are not active in a fresh clone until they are installed
once:

```bash
pre-commit install
```

Formatting needs no flags: shfmt reads the style from `.editorconfig`, so
`shfmt -w <file>` and the hook agree by construction.

## License

BSD 3-Clause. See [LICENSE](LICENSE) for details.
