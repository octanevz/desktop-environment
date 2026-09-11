#!/bin/bash
set -euo pipefail

# =============================================================================
# This script performs the following tasks:
# - Stops when ~/.ssh holds no private key, before anything is written
# - Asks for the Git identity (name and email) and sets it
# - Sets the Git behaviour this setup assumes (rebase on pull, prune on
#   fetch, an upstream on the first push, and friends)
# - Configures delta as the pager when it is installed
# - Registers the Git LFS filters when git-lfs is installed
# - Registers the GitHub CLI as the credential helper for HTTPS remotes
# - Offers to add the SSH keys found in ~/.ssh to the agent
#
# It does NOT configure commit signing: signing everything by default fails
# closed wherever the key cannot be reached - an SSH session, cron, a
# container - and a commit is refused rather than made unsigned. Sign the
# commits that want it with "git commit -S" instead.
#
# Run this AFTER setup-00-packages.sh (git, git-delta, git-lfs),
# setup-01-devtools.sh (Neovim as the editor, the GitHub CLI) and
# setup-07-configs.sh.
#
# Unlike the other scripts here, this one ASKS rather than assuming: the
# identity is personal, and hardcoding one would put the author's address into
# every fork's commits. Existing values are offered as the default, so
# re-running is a matter of pressing Enter. Set GIT_USER_NAME and
# GIT_USER_EMAIL in the environment to skip the questions entirely:
#
#   GIT_USER_NAME="Ada Lovelace" GIT_USER_EMAIL=ada@example.com ./setup-08-git.sh
#
# With no terminal attached, the script uses those variables and whatever is
# already configured, and stops if that leaves the identity unset.
#
# Every setting is written with "git config --global" rather than by copying
# a complete ~/.gitconfig into place. A .gitconfig is not only ours: "gh auth
# setup-git" writes a credential helper into it, JetBrains and VS Code write
# their merge tools, and a machine picks up host-specific remotes over time.
# Copying a file in would silently delete all of that, so each key is set on
# its own and anything not listed here is left untouched.
#
# The script is therefore safe to re-run - it reports only the keys whose
# value actually changed.
# =============================================================================

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
# The identity is asked for below; these are only the defaults for the
# environment variables that skip the questions.
GIT_USER_NAME="${GIT_USER_NAME:-}"
GIT_USER_EMAIL="${GIT_USER_EMAIL:-}"

# The default branch new repositories get, and the editor Git opens for commit
# messages and interactive rebases. nvim comes from setup-01-devtools.sh.
GIT_DEFAULT_BRANCH="main"
GIT_EDITOR="nvim"

SSH_DIR="$HOME/.ssh"

# The steps that could not be carried out, as opposed to the ones deliberately
# turned down. The script records itself as complete only when this is empty,
# so a step that was blocked by something fixable - an unauthenticated gh, a
# key that is not there yet - is retried on the next plain run instead of
# needing --force that nobody remembers to pass.
#
# Nothing that is not persistent configuration lands here, such as which keys
# the running agent happens to hold, and neither does a tool that is simply
# not installed - absent reads as unwanted.
INCOMPLETE=()

# Whether there is someone to ask. Everything interactive below is skipped
# when there is not, so the script still runs unattended.
if [ -t 0 ]; then
    INTERACTIVE=1
else
    INTERACTIVE=0
fi

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
setup_begin "$@"

# -----------------------------------------------------------------------------
# Set one global configuration key
# -----------------------------------------------------------------------------
# Reports what changed and stays quiet about what did not, so a re-run prints
# the difference rather than the whole configuration. --get exits non-zero
# when the key is unset, which is not an error here - hence the || true.
set_config() {
    local key=$1 value=$2 current

    current="$(git config --global --get "$key" || true)"

    if [ "$current" = "$value" ]; then
        return
    fi

    # --replace-all, not a plain set: a key that somehow ended up with
    # several values (a hand-edited .gitconfig, an include) makes a single
    # value assignment fail outright - "cannot overwrite multiple values".
    git config --global --replace-all "$key" "$value"

    if [ -n "$current" ]; then
        log "  $key: $current -> $value"
    else
        log "  $key = $value"
    fi
}

# -----------------------------------------------------------------------------
# Ask for one value
# -----------------------------------------------------------------------------
# Prints the prompt with the default in brackets and returns what was typed,
# or the default when the answer is empty. Asks again while the answer is
# empty and there is no default, so the caller always gets something back.
#
# The answer is returned in ASK_RESULT rather than printed, so that end of
# input can be reported as a failure: read through a command substitution, a
# failing read could not stop the caller - set -e does not cross that
# boundary - and Ctrl-D at a prompt with no default spun here forever.
#
# Returns non-zero when there is nothing more to read; every caller must
# handle that.
ask() {
    local prompt=$1 default=${2:-}

    while true; do
        if [ -n "$default" ]; then
            if ! read -r -p "$prompt [$default]: " ASK_RESULT; then
                echo >&2
                echo "  End of input - nothing to read." >&2
                return 1
            fi
            ASK_RESULT="${ASK_RESULT:-$default}"
        else
            if ! read -r -p "$prompt: " ASK_RESULT; then
                echo >&2
                echo "  End of input - nothing to read." >&2
                return 1
            fi
        fi

        if [ -n "$ASK_RESULT" ]; then
            return 0
        fi

        echo "  A value is required." >&2
    done
}

# -----------------------------------------------------------------------------
# Find the SSH keys
# -----------------------------------------------------------------------------
# The keys are restored by hand rather than generated here, so this only looks
# at what is already in ~/.ssh. A private key is recognised either by having a
# .pub next to it or by its PEM header, which covers keys whose public half
# was not copied along. Everything OpenSSH keeps in that directory for its own
# purposes is skipped by name.
#
# Prints one path per line; prints nothing at all when there is no ~/.ssh.
discover_ssh_keys() {
    local file

    [ -d "$SSH_DIR" ] || return 0

    for file in "$SSH_DIR"/*; do
        # An unmatched glob comes back as the pattern itself, which is not a
        # file - so this also covers an empty directory.
        [ -f "$file" ] || continue

        case "${file##*/}" in
            *.pub | known_hosts* | config | authorized_keys | environment | rc | agent-* | *.bak-*)
                continue
                ;;
        esac

        # Readable, because an unusable key must not satisfy the gate below.
        #
        # This is candidate detection and nothing more: the names above are
        # excluded by name rather than by content, and a file that merely has
        # a .pub beside it is taken at its word. Neither test proves a usable
        # private key is there - only that something in this directory means
        # to be one.
        [ -r "$file" ] || continue

        if [ -f "$file.pub" ] || head -n 1 "$file" 2> /dev/null | grep -q "PRIVATE KEY"; then
            printf '%s\n' "$file"
        fi
    done
}

SSH_KEYS=()
while IFS= read -r line; do
    SSH_KEYS+=("$line")
done < <(discover_ssh_keys)

# -----------------------------------------------------------------------------
# Stop when there are no SSH keys
# -----------------------------------------------------------------------------
# Checked here, before a single setting has been written, so a machine whose
# keys have not been restored yet is left exactly as it was rather than half
# configured.
#
# The check is for a PRIVATE key: a lone .pub cannot be added to the agent, so
# a ~/.ssh holding only public halves counts as empty here.
#
# The way through for a machine that genuinely has no keys - one that talks to
# its remotes over HTTPS through the GitHub CLI - is to say so explicitly:
#
#   ALLOW_NO_SSH_KEYS=1 ./setup-08-git.sh
#
# which is also the way through for keys that live outside ~/.ssh entirely -
# resident on a hardware token, or held by an agent this script cannot see.
if [ ${#SSH_KEYS[@]} -eq 0 ] && [ "${ALLOW_NO_SSH_KEYS:-0}" != "1" ]; then
    echo "No SSH private keys found in $SSH_DIR." >&2
    echo "Restore your keys there first, then run this script again - nothing" >&2
    echo "has been configured yet." >&2
    echo >&2
    echo "To configure Git anyway (HTTPS remotes, or keys held elsewhere):" >&2
    echo "  ALLOW_NO_SSH_KEYS=1 $0" >&2
    exit 1
fi

if [ ${#SSH_KEYS[@]} -gt 0 ]; then
    log "Found ${#SSH_KEYS[@]} SSH key(s) in $SSH_DIR."
fi

# -----------------------------------------------------------------------------
# Set the identity
# -----------------------------------------------------------------------------
# The order is: what the environment says, then what Git already has, then
# what is typed in. So a machine that is already configured only needs Enter,
# and a fresh one is asked once.
log "Setting the Git identity..."

CURRENT_NAME="$(git config --global --get user.name || true)"
CURRENT_EMAIL="$(git config --global --get user.email || true)"

if [ -z "$GIT_USER_NAME" ] && [ "$INTERACTIVE" = "1" ]; then
    ask "  Your name" "$CURRENT_NAME" || exit 1
    GIT_USER_NAME="$ASK_RESULT"
fi
GIT_USER_NAME="${GIT_USER_NAME:-$CURRENT_NAME}"

if [ -z "$GIT_USER_EMAIL" ] && [ "$INTERACTIVE" = "1" ]; then
    while true; do
        ask "  Your email" "$CURRENT_EMAIL" || exit 1
        GIT_USER_EMAIL="$ASK_RESULT"
        # Deliberately loose: this catches a typed-in mistake such as a
        # missing @, not every address RFC 5322 forbids.
        if [[ "$GIT_USER_EMAIL" == *@*.* && "$GIT_USER_EMAIL" != *" "* ]]; then
            break
        fi
        echo "  That does not look like an email address." >&2
    done
fi
GIT_USER_EMAIL="${GIT_USER_EMAIL:-$CURRENT_EMAIL}"

# Without a terminal and without either source, there is nothing to set, and
# committing with a guessed identity is worse than stopping.
if [ -z "$GIT_USER_NAME" ] || [ -z "$GIT_USER_EMAIL" ]; then
    echo "No Git identity available and no terminal to ask on." >&2
    echo "Set GIT_USER_NAME and GIT_USER_EMAIL, or run this from a terminal." >&2
    exit 1
fi

# From here on this run is no longer "the run that completed earlier", so the
# marker goes before the first write rather than at the end: a --force run
# that dies in the middle - or simply ends incomplete - would otherwise leave
# it standing, and the next plain run would exit at once believing the work
# was done. setup_end writes it again when the run really does finish.
#
# Deliberately below the prompts and their exit paths: abandoning the script
# at the name prompt changes nothing, and must therefore lose nothing either.
setup_invalidate

set_config user.name "$GIT_USER_NAME"
set_config user.email "$GIT_USER_EMAIL"
log "  Commits are authored as $GIT_USER_NAME <$GIT_USER_EMAIL>."

# -----------------------------------------------------------------------------
# Set the behaviour
# -----------------------------------------------------------------------------
# Only settings that change what a bare Git command does, each one because the
# default is a worse fit for this setup - not a dump of every knob Git has.
log "Setting the Git behaviour..."

# Branch and remote handling
set_config init.defaultBranch "$GIT_DEFAULT_BRANCH"
set_config core.editor "$GIT_EDITOR"

# A pull is a rebase, never an implicit merge commit; autostash lets it run
# with a dirty tree, which is how a pull is usually reached for.
set_config pull.rebase true
set_config rebase.autoStash true

# "git push" on a new branch creates it on the remote instead of failing with
# the "--set-upstream" hint. push.default is deliberately NOT set: "simple" has
# been Git's own default since 2.0, so setting it would only be dead config.
set_config push.autoSetupRemote true

# Remote-tracking branches for branches deleted upstream are cleared on every
# fetch, which is what keeps clean_gone-style cleanups honest. Only the
# remote-tracking refs: fetch.pruneTags is deliberately NOT set, because it
# also deletes local tags that are not on the remote - including one just
# created and not yet pushed.
set_config fetch.prune true

# Branches are listed most recently worked on first rather than alphabetically.
set_config branch.sort -committerdate

# Conflict resolutions are recorded and replayed, so the same conflict in a
# rebased or repeatedly merged branch only has to be solved once. A replayed
# resolution is left unstaged: rerere.autoUpdate is deliberately NOT set, so
# what rerere reapplies is reviewed before it goes into a commit.
set_config rerere.enabled true

# Diff and merge output
# histogram produces markedly more readable hunks than the default myers for
# code that was moved or re-indented, and colorMoved distinguishes a block
# that moved from one that was rewritten.
set_config diff.algorithm histogram
set_config diff.colorMoved zebra
set_config diff.renames copies

# zdiff3 shows the common ancestor in a conflict, without the noise diff3
# leaves in; it is what makes a conflict readable without opening a merge tool.
set_config merge.conflictstyle zdiff3

# Dates in the ISO form the eza aliases and the tmux status line already use.
set_config log.date iso
set_config column.ui auto

# Mistyped subcommands are listed rather than run: 0.1s would auto-execute the
# guess, "prompt" asks first.
set_config help.autocorrect prompt

# -----------------------------------------------------------------------------
# Configure delta as the pager
# -----------------------------------------------------------------------------
# git-delta comes from setup-00-packages.sh. It is checked for rather than
# assumed: pointing core.pager at a binary that is not there breaks every diff
# command, which is a bad trade for a cosmetic improvement. The lazygit that
# setup-01-devtools.sh installs picks delta up through this same
# configuration.
if command -v delta > /dev/null 2>&1; then
    log "Configuring delta as the pager..."
    set_config core.pager delta
    set_config interactive.diffFilter "delta --color-only"

    # navigate binds n and N inside the pager to jump between files.
    set_config delta.navigate true
    set_config delta.line-numbers true
    set_config delta.hyperlinks true
else
    log "delta is not installed - leaving the default pager in place."
    log "  Install it with: sudo apt install -y git-delta"
fi

# -----------------------------------------------------------------------------
# Register the Git LFS filters
# -----------------------------------------------------------------------------
# git-lfs comes from setup-00-packages.sh. Without the filters registered, a
# clone of a repository that uses LFS succeeds and leaves every large file as a
# one-line text pointer - which is why this is set up before such a repository
# is ever met, rather than after the confusing part.
#
# --skip-repo writes the global filter configuration and nothing else: a plain
# "git lfs install" also drops hooks into whatever repository happens to be the
# working directory, which is not this script's business.
#
# Checked rather than run blindly, so a re-run stays as quiet as set_config
# does. filter.lfs.clean is the key "git lfs install" sets first.
if ! command -v git-lfs > /dev/null 2>&1; then
    log "git-lfs is not installed - skipping the LFS filters."
    log "  Install it with: sudo apt install -y git-lfs"
elif [ -n "$(git config --global --get filter.lfs.clean || true)" ]; then
    log "The Git LFS filters are already registered."
else
    log "Registering the Git LFS filters..."
    git lfs install --skip-repo
fi

# -----------------------------------------------------------------------------
# Register the GitHub CLI as the credential helper
# -----------------------------------------------------------------------------
# This is what makes an HTTPS remote work without a password prompt or a
# personal access token in a file. It is skipped rather than attempted when gh
# is not logged in, because "gh auth setup-git" writes a helper that then fails
# on every push.
if ! command -v gh > /dev/null 2>&1; then
    log "The GitHub CLI is not installed - skipping the credential helper."
elif gh auth status --hostname github.com > /dev/null 2>&1; then
    log "Registering the GitHub CLI as the credential helper..."
    # Both calls name the host: a bare "gh auth status" reports on every
    # account gh knows, so an unrelated expired login elsewhere would be
    # taken for github.com being unauthenticated.
    gh auth setup-git --hostname github.com
    log "  HTTPS remotes on github.com authenticate through gh."
else
    # Treated as a prerequisite, not as a choice: while gh is installed and
    # unauthenticated this script reports itself incomplete on EVERY run.
    # Authenticate, or remove gh if this machine is deliberately not using it.
    log "The GitHub CLI is not logged in - skipping the credential helper."
    INCOMPLETE+=("the GitHub CLI credential helper - run 'gh auth login --hostname github.com'")
fi

# -----------------------------------------------------------------------------
# Add the SSH keys to the agent
# -----------------------------------------------------------------------------
# ssh-add talks to the agent named by SSH_AUTH_SOCK, which a GNOME session
# provides through gnome-keyring (installed by setup-00-packages.sh). Over SSH
# or on a bare TTY there may be none, and starting one here would be useless:
# the agent would belong to this script's own process and die with it, taking
# the variable the parent shell never saw with it.
#
# Note what this does NOT do: keys added here live in the running agent only,
# until the next logout. Put "AddKeysToAgent yes" in ~/.ssh/config to have
# every key added on first use instead, which is the setting that makes this
# step unnecessary from then on.
if [ ${#SSH_KEYS[@]} -eq 0 ]; then
    log "No SSH keys found in $SSH_DIR - skipping the agent."
elif [ -z "${SSH_AUTH_SOCK:-}" ]; then
    log "No SSH agent in this session (SSH_AUTH_SOCK is unset)."
    log "  Found ${#SSH_KEYS[@]} key(s); add them from a desktop session, or run:"
    # %q on every path: these lines are meant to be copied, and a key whose
    # name contains a space would otherwise be pasted as two arguments.
    QUOTED_KEYS=""
    for key in "${SSH_KEYS[@]}"; do
        QUOTED_KEYS="$QUOTED_KEYS $(printf '%q' "$key")"
    done
    log "    eval \"\$(ssh-agent -s)\" && ssh-add$QUOTED_KEYS"
elif [ "$INTERACTIVE" != "1" ]; then
    log "Not running on a terminal - not adding keys to the agent."
else
    log "Adding the SSH keys to the agent..."

    # The fingerprints already loaded, so a key is not offered twice. ssh-add
    # -l exits 1 for an empty agent and 2 when it cannot reach one; neither is
    # an error here, and the empty result simply offers every key.
    LOADED="$(ssh-add -l 2> /dev/null || true)"

    for key in "${SSH_KEYS[@]}"; do
        # Field 2 of ssh-keygen -l is the SHA256 fingerprint, and it is the
        # same for the private key and its .pub, so the agent listing can be
        # matched against it directly.
        # || true: under pipefail a candidate ssh-keygen cannot read - a
        # file that only looked like a key - would fail this assignment and,
        # with set -e, abort the script here, after everything above has
        # already been written. A missing fingerprint only costs the
        # duplicate check.
        FINGERPRINT="$(ssh-keygen -lf "$key" 2> /dev/null | awk '{print $2}' || true)"

        if [ -n "$FINGERPRINT" ] && [[ "$LOADED" == *"$FINGERPRINT"* ]]; then
            log "  ${key##*/} is already in the agent."
            continue
        fi

        # ssh-add refuses a key others can read, with an error that does not
        # mention the fix - so the fix is offered before it has a chance to.
        #
        # -L because a key is often a symlink into a synced directory, and the
        # link's own mode is a meaningless 777. What ssh-add actually objects
        # to is any group or other bit, so that is what is tested rather than
        # an exact 600: 700 is just as acceptable.
        # || continue rather than letting set -e abort: the file can be gone
        # by now, or be a symlink whose target is.
        PERMISSIONS="$(stat -Lc '%a' "$key")" || continue
        if [ $((8#$PERMISSIONS & 077)) -ne 0 ]; then
            log "  ${key##*/} is mode $PERMISSIONS - group or other bits are set."
            log "    Fix it with: chmod 600 $(printf '%q' "$key")"
            continue
        fi

        # End of input declines, rather than aborting a script that has
        # already written its configuration.
        read -r -p "  Add ${key##*/} to the agent? (y/N): " reply || reply=""
        if [[ "$reply" =~ ^[JjYy]$ ]]; then
            # A passphrase-protected key asks for it here, which is why this
            # is not run unattended. A refused or mistyped passphrase must not
            # take the whole script down with it.
            if ssh-add "$key"; then
                log "    Added ${key##*/}."
            else
                log "    Could not add ${key##*/} - skipping it."
            fi
        fi
    done
fi

# -----------------------------------------------------------------------------
# Verify the installation
# -----------------------------------------------------------------------------
log "Git configured successfully!"
log "Review the result with: git config --global --list"

# Everything above has already been written either way - this only decides
# whether the script counts as done. Left unrecorded, it runs again on the
# next plain invocation and picks up what is still missing; every step it
# performs is idempotent, so the repeat costs nothing.
if [ ${#INCOMPLETE[@]} -gt 0 ]; then
    echo >&2
    echo "Not everything could be set up:" >&2
    for item in "${INCOMPLETE[@]}"; do
        echo "  - $item" >&2
    done
    echo >&2
    echo "Fix the above, then run $0 again - it is NOT recorded as complete," >&2
    echo "so no --force is needed." >&2
    exit 0
fi

setup_end
