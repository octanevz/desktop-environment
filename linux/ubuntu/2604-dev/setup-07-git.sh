#!/bin/bash
set -euo pipefail

# =============================================================================
# This script performs the following tasks:
# - Asks for the Git identity (name and email) and sets it
# - Sets the Git behaviour this setup assumes (rebase on pull, prune on
#   fetch, an upstream on the first push, and friends)
# - Configures delta as the pager when it is installed
# - Registers the Git LFS filters when git-lfs is installed
# - Registers the GitHub CLI as the credential helper for HTTPS remotes
#
# It does NOT touch SSH: the keys are restored into ~/.ssh and added to the
# agent by hand, which is a per-login matter rather than configuration. Put
# "AddKeysToAgent yes" in ~/.ssh/config to have every key added on first use.
#
# It does NOT configure commit signing: signing everything by default fails
# closed wherever the key cannot be reached - an SSH session, cron, a
# container - and a commit is refused rather than made unsigned. Sign the
# commits that want it with "git commit -S" instead.
#
# Run this AFTER setup-00-packages.sh (git, git-delta, git-lfs),
# setup-01-devtools.sh (Neovim as the editor, the GitHub CLI) and
# setup-06-configs.sh.
#
# Unlike the other scripts here, this one ASKS rather than assuming: the
# identity is personal, and hardcoding one would put the author's address into
# every fork's commits. Existing values are offered as the default, so
# re-running is a matter of pressing Enter. Set GIT_USER_NAME and
# GIT_USER_EMAIL in the environment to skip the questions entirely:
#
#   GIT_USER_NAME="Ada Lovelace" GIT_USER_EMAIL=ada@example.com ./setup-07-git.sh
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

# The steps that could not be carried out, as opposed to the ones deliberately
# turned down. The script records itself as complete only when this is empty,
# so a step that was blocked by something fixable - an unauthenticated gh -
# is retried on the next plain run instead of needing --force that nobody
# remembers to pass.
#
# A tool that is simply not installed does not land here - absent reads as
# unwanted.
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
# Set the identity
# -----------------------------------------------------------------------------
# The order is: what the environment says, then what Git already has, then
# what is typed in. So a machine that is already configured only needs Enter,
# and a fresh one is asked once.
step "Set the identity"
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
step "Set the behaviour"
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
step "Configure delta as the pager"
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
step "Register the Git LFS filters"
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
step "Register the GitHub CLI as the credential helper"
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
    #
    # The suggested command names every choice the login wizard would
    # otherwise ask about. --git-protocol ssh, because the remotes here are
    # SSH and the keys are already in ~/.ssh; --skip-ssh-key, because with
    # SSH chosen the wizard next offers to generate a key and upload it to
    # GitHub - the key is there already, and a second one would only clutter
    # the account.
    log "The GitHub CLI is not logged in - skipping the credential helper."
    INCOMPLETE+=("the GitHub CLI credential helper - run 'gh auth login --hostname github.com --git-protocol ssh --skip-ssh-key --web'")
fi

# -----------------------------------------------------------------------------
# Verify the installation
# -----------------------------------------------------------------------------
step "Verify the installation"
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
