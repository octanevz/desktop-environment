#!/bin/bash

# =============================================================================
# Sourced by the numbered setup scripts - not run on its own. It provides:
# - log: prints a green status line
# - setup_begin: stops the script when a lower-numbered script has not
#   completed yet, or when the script itself has already completed
# - setup_end: records the script's completion
#
# Completion is recorded as one file per script under STATE_DIR, named after
# the script and holding the completion time. A script whose file exists
# exits at once; pass --force (or FORCE=1) to run it again, or delete the
# file. A numbered script also requires the file of every lower-numbered
# script, so the sequence is run in order and no step is skipped.
#
# The scripts that are meant to run repeatedly - setup-agents.sh, update-sys.sh
# and update-all.sh - do not source this file.
# =============================================================================

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/desktop-environment"
SETUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_NAME="$(basename "$0" .sh)"

log() {
    echo -e "\e[32m$1\e[0m"
}

# Call at the top of a numbered script, after its own argument parsing, with
# the script's arguments. Recognises --force itself so that the scripts
# without an argument parser get it too; a script's own FORCE=1 counts.
setup_begin() {
    local arg script name number marker
    for arg in "$@"; do
        case "$arg" in
            -f | --force)
                FORCE=1
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

# Call once the script has done everything it is for - before a reboot
# prompt, since that never returns.
setup_end() {
    mkdir -p "$STATE_DIR"
    date '+%Y-%m-%d %H:%M' > "$STATE_DIR/$SETUP_NAME.done"
    log "Completion recorded in $STATE_DIR/$SETUP_NAME.done."
}
