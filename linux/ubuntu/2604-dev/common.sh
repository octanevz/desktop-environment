#!/bin/bash

# =============================================================================
# Sourced by the numbered setup scripts - not run on its own. It provides:
# - log: prints a green status line
# - step: prints a colour-ruled header that opens a step of the script
# - sudo_keepalive: asks for the sudo password once, up front, and keeps the
#   sudo timestamp fresh until the script exits
# - tmp_dir: creates the script's scratch directory for downloads, TMP_DIR,
#   which is removed when the script exits
# - SETUP_DIR, the directory the scripts live in, and ZSH_COMPLETIONS, the
#   directory the generated Zsh completions go to
# - setup_begin: parses the arguments, then stops the script when a
#   lower-numbered script has not completed yet, or when the script itself
#   has already completed
# - setup_end: records the script's completion
#
# Completion is recorded as one file per script under STATE_DIR, named after
# the script and holding the completion time. A script whose file exists
# exits at once; pass --force (or FORCE=1) to run it again, or delete the
# file. A numbered script also requires the file of every lower-numbered
# script, so the sequence is run in order and no step is skipped. The
# backups the scripts take before changing something live under STATE_DIR
# too, each kind in its own subdirectory.
#
# The scripts that are meant to run repeatedly - setup-agents.sh, update-sys.sh
# and update-all.sh - source this file for log and step only and never call
# setup_begin or setup_end, so they carry no marker and run every time.
#
# Sourcing this file sets the EXIT trap that ends the sudo loop and removes
# TMP_DIR; no script sets an EXIT trap of its own, which would replace it.
# =============================================================================

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/desktop-environment"
SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_NAME="$(basename "$0" .sh)"

# Where the generated Zsh completions go (setup-01-devtools.sh, setup-03-
# alacritty.sh and update-all.sh write them): Oh My Zsh's custom/completions
# directory, which oh-my-zsh.sh puts on fpath BEFORE it runs compinit - a
# directory appended to fpath from the end of .zshrc would be too late, since
# compinit only registers what is on fpath when it runs.
# shellcheck disable=SC2034 # used by the scripts that source this file
ZSH_COMPLETIONS="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/completions"

# Set by sudo_keepalive and tmp_dir; the trap below reads them.
SUDO_KEEPALIVE_PID=""
TMP_DIR=""

# The trap's kill fails when the loop has already ended, and under set -e a
# failing command in an EXIT trap would replace the script's exit status
# with 1 - hence the || true. A script that ends in exec (the reboots, the
# log-out) never runs the trap: the loop then ends on its own, and TMP_DIR
# is left to /tmp, which Ubuntu clears at boot.
common_cleanup() {
    if [ -n "$SUDO_KEEPALIVE_PID" ]; then
        kill "$SUDO_KEEPALIVE_PID" 2> /dev/null || true
    fi
    if [ -n "$TMP_DIR" ]; then
        rm -rf "$TMP_DIR"
    fi
}
trap common_cleanup EXIT

# printf, not echo -e: echo -e interprets backslashes in what it is given, so
# a path containing one - or the output of printf '%q' - would be printed
# wrong, and a command line printed for the user to copy would be wrong with
# it. No caller passes an escape sequence of its own.
log() {
    printf '\033[32m%s\033[0m\n' "$1"
}

# A header for each step of a script: a blank line, a rule of "/" in gradient
# colours, the title in bold white let into a second such rule, the rule
# again, a blank line. The rule is 79 characters, the width the comment rules
# in the scripts have.
step() {
    # A 256-colour gradient from orange through yellow and green to cyan,
    # stretched once over the width of the rule.
    local colors=(208 214 220 226 190 154 118 82 46 47 48 49 50 51)
    local i seg rule="" tail=""
    for ((i = 0; i < 79; i++)); do
        printf -v seg '\033[38;5;%sm/' "${colors[i * ${#colors[@]} / 79]}"
        rule+="$seg"
        # The title line is the rule with the title in bold white let into
        # it: "// ", the title, a space, then slashes to the right edge in
        # the colours those columns have in the rule.
        if [ "$i" -ge $((${#1} + 4)) ]; then
            tail+="$seg"
        fi
    done
    printf '\n%s\033[0m\n' "$rule"
    printf '\033[38;5;%sm// \033[1;37m%s\033[0m %s\033[0m\n' \
        "${colors[0]}" "$1" "$tail"
    printf '%s\033[0m\n\n' "$rule"
}

# Call at the top of a script that uses sudo, after setup_begin, so that the
# password is asked once, at the start, rather than at the first sudo call -
# which may come minutes into a long download or build, with nobody watching
# the terminal. A background loop refreshes the sudo timestamp every minute
# for as long as the script runs, so it cannot expire (15 minutes by default)
# partway through and ask again. The loop is killed by the EXIT trap above
# and also watches the script's PID, in case the trap never runs (a script
# that ends in exec, or is killed); -n makes sure it never prompts on its
# own.
#
# When the timestamp is already valid - update-all.sh calls update-sys.sh,
# and both call this - "sudo -n -v" succeeds and the message is skipped. It
# is -v, not a NOPASSWD-able command like true, that is tested: only -v
# proves the authentication itself is cached.
#
# The loop's output goes to /dev/null so that the sleep it may leave behind
# for up to a minute holds no pipe open when the script's output is piped.
sudo_keepalive() {
    if ! sudo -n -v 2> /dev/null; then
        log "Some steps need root - enter your password once for sudo."
        sudo -v
    fi
    (
        while kill -0 "$$" 2> /dev/null; do
            sudo -n -v || exit
            sleep 60
        done
    ) > /dev/null 2>&1 &
    SUDO_KEEPALIVE_PID=$!
}

# Call before the first download. Creates TMP_DIR, a private directory under
# mktemp's rules, so that downloads never land on fixed names in /tmp that
# another user or an earlier run could have left there; the EXIT trap above
# removes it. Calling it again is harmless.
tmp_dir() {
    if [ -z "$TMP_DIR" ]; then
        TMP_DIR="$(mktemp -d)"
    fi
}

# Call at the top of a numbered script with the script's arguments. The only
# argument is -f/--force; anything else stops the script with a usage line,
# so a typo cannot be taken for a plain run. A script's own FORCE=1 counts
# the same as the flag.
setup_begin() {
    local arg script name number marker
    for arg in "$@"; do
        case "$arg" in
            -f | --force)
                FORCE=1
                ;;
            *)
                echo "Unknown argument: $arg" >&2
                echo "Usage: $0 [--force]" >&2
                exit 1
                ;;
        esac
    done
    FORCE="${FORCE:-0}"

    # 10# reads the two-digit numbers as decimal; 08 and 09 would otherwise
    # be taken for (invalid) octal.
    number=$((10#$(echo "$SETUP_NAME" | cut -d- -f2)))
    for script in "$SETUP_DIR"/setup-[0-9][0-9]-*.sh; do
        name="$(basename "$script" .sh)"
        if [ $((10#$(echo "$name" | cut -d- -f2))) -ge "$number" ]; then
            continue
        fi
        if [ ! -f "$STATE_DIR/$name.done" ]; then
            echo "$SETUP_NAME.sh: $name.sh has not completed yet - run it first." >&2
            exit 1
        fi
    done

    marker="$STATE_DIR/$SETUP_NAME.done"
    if [ -f "$marker" ] && [ "$FORCE" != "1" ]; then
        log "$SETUP_NAME.sh already completed on $(cat "$marker")."
        log "Re-run with --force to run it again."
        exit 0
    fi
}

# Call at the point a script is about to change the system, after its
# prerequisite checks and after every early exit that leaves the machine as it
# found it. It drops the completion marker, so that from here until setup_end
# writes it again nothing claims this script has completed.
#
# Without it, --force walks past an existing marker without clearing it: a
# forced re-run that then dies halfway - a failed download, a Ctrl-C, a power
# cut - leaves the marker of the earlier, successful run in place, and the
# next plain run exits at once believing the work was done.
#
# Placement is the whole point. Too early and abandoning the script at a
# prompt, or a prerequisite check that stops before touching anything,
# destroys a marker that was still true.
setup_invalidate() {
    rm -f "$STATE_DIR/$SETUP_NAME.done"
}

# Call once the script has done everything it is for - before a reboot
# prompt, since that never returns.
setup_end() {
    mkdir -p "$STATE_DIR"
    date '+%Y-%m-%d %H:%M' > "$STATE_DIR/$SETUP_NAME.done"
    log "Completion recorded in $STATE_DIR/$SETUP_NAME.done."
}
