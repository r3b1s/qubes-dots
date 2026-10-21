#!/usr/bin/env bash
# Run in dom0. Re-pulls one or more repos that already live in ~/Dotfiles: runs
# `git pull` inside the source AppVM, tar-copies the result back into dom0,
# and optionally re-runs each repo's install.sh and reloads i3.
#
# This is the iterate step. dom0-clone-dots.sh is the bootstrap (first clone);
# this is what you run the twentieth time. git stays in the AppVM — dom0 never
# needs it, and never gets a network interface.
#
# Usage:
#   ./dom0-sync-dots.sh <folder1,folder2,...> <source-vm> [--dirty] [--install] [--reload]
#
# Each folder is replaced wholesale, not merged: the new tree is extracted
# beside the old one and swapped in, so a file deleted upstream disappears here
# too. Local edits inside ~/Dotfiles/<folder> in dom0 are destroyed. Edit in the
# AppVM, sync down; never the reverse (that is dom0-push-dots.sh).

set -euo pipefail

# dom0 rpc services run as root, so reaching this script through dev.Shell would
# put $HOME at /root: the tree would land in /root/Dotfiles and install.sh would
# symlink the dots into /root/.config/i3, where the i3 running as the desktop
# user never looks. It would all appear to succeed. Re-exec as that user so the
# dom0-terminal and dev.Shell paths do the same thing.
QUBES_USER="${QUBES_USER:-user}"
if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    if ! id -u "$QUBES_USER" >/dev/null 2>&1; then
        echo "error: no such dom0 user: '$QUBES_USER' — set QUBES_USER" >&2
        exit 1
    fi
    exec runuser -u "$QUBES_USER" -- \
        env DISPLAY="${DISPLAY:-:0}" QUBES_USER="$QUBES_USER" \
        "$(readlink -f "$0")" "$@"
fi

print_help() {
    cat <<'EOF'
Usage: ./dom0-sync-dots.sh <folder1,folder2,...> <source-vm> [options]

Run in dom0. Runs `git pull` in each folder inside <source-vm>, copies the
result back into dom0's ~/Dotfiles, replacing each folder wholesale.

Arguments:
  folder1,folder2,...  comma-separated folder names, relative to ~/Dotfiles
  source-vm            AppVM holding the git checkouts

Options:
  --dirty      skip `git pull`; copy the AppVM's working tree as it stands
  --install    run ./install.sh in each synced folder, if it has one
  --reload     run `i3-msg reload` once, after all folders are synced
  -h, --help   show this help text and exit

Local edits under dom0's ~/Dotfiles/<folder> are destroyed. Sync is one-way.
EOF
}

case "${1:-}" in
    -h|--help)
        print_help
        exit 0
        ;;
esac

if [[ $# -lt 2 ]]; then
    echo "usage: $0 <folder1,folder2,...> <source-vm> [--dirty] [--install] [--reload]" >&2
    exit 1
fi

FOLDERS_ARG=$1
SOURCE_VM=$2
shift 2

DIRTY=false
RUN_INSTALL=false
RELOAD=false
for arg in "$@"; do
    case "$arg" in
        --dirty)   DIRTY=true ;;
        --install) RUN_INSTALL=true ;;
        --reload)  RELOAD=true ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            echo "error: unknown argument: $arg" >&2
            exit 1
            ;;
    esac
done

DOTS_DIR="$HOME/Dotfiles"
REMOTE_DOTS_DIR=/home/user/Dotfiles

# POSIX-sh-safe single-quote escaping for building remote command strings.
shquote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

IFS=',' read -ra FOLDERS <<< "$FOLDERS_ARG"

# Distinguish "no such qube" from "no such folder" up front. Checked separately
# because a bare qvm-run failure cannot tell the two apart, and the wrong error
# sends you looking in the wrong machine.
if ! qvm-check --quiet "$SOURCE_VM" 2>/dev/null; then
    echo "error: no such qube: $SOURCE_VM" >&2
    exit 1
fi

# Resolve and validate every folder before touching anything, so a typo in the
# third name cannot leave the first two swapped and the third missing.
declare -a NAMES=()
for folder in "${FOLDERS[@]}"; do
    folder="$(echo "$folder" | xargs)"
    [[ -z "$folder" ]] && continue
    case "$folder" in
        */*|.|..)
            echo "error: '$folder' must be a bare folder name under ~/Dotfiles" >&2
            exit 1
            ;;
    esac
    if ! qvm-run --pass-io "$SOURCE_VM" \
        "test -d $(shquote "$REMOTE_DOTS_DIR/$folder")"; then
        echo "error: $SOURCE_VM:$REMOTE_DOTS_DIR/$folder does not exist" >&2
        echo "       bootstrap it first with dom0-clone-dots.sh" >&2
        exit 1
    fi
    NAMES+=("$folder")
done

[[ ${#NAMES[@]} -gt 0 ]] || { echo "error: no folders given" >&2; exit 1; }

mkdir -p "$DOTS_DIR"

if ! $DIRTY; then
    for folder in "${NAMES[@]}"; do
        echo "==> git pull in $SOURCE_VM:$REMOTE_DOTS_DIR/$folder"
        qvm-run --pass-io "$SOURCE_VM" \
            "cd $(shquote "$REMOTE_DOTS_DIR/$folder") && git pull --ff-only"
    done
fi

for folder in "${NAMES[@]}"; do
    echo "==> copying $folder from $SOURCE_VM"

    # Extract beside the target, then swap. The old tree is removed only after
    # the new one has landed whole, so an interrupted transfer leaves dom0's
    # working copy alone rather than half-replaced.
    staging="$DOTS_DIR/.sync.$folder.$$"
    rm -rf "$staging"
    mkdir -p "$staging"
    trap 'rm -rf "$staging"' EXIT

    qvm-run --pass-io "$SOURCE_VM" \
        "tar -cf - -C $(shquote "$REMOTE_DOTS_DIR") $(shquote "$folder")" \
        | tar -xf - -C "$staging"

    [[ -d "$staging/$folder" ]] || {
        echo "error: $folder: transfer produced no such directory" >&2
        exit 1
    }

    # Belt and braces before an rm -rf: refuse anything that is not literally
    # the path we built two lines up.
    target="$DOTS_DIR/$folder"
    [[ "$target" == "$DOTS_DIR/"* && "$target" != "$DOTS_DIR/" ]] || {
        echo "error: refusing to remove '$target'" >&2
        exit 1
    }

    rm -rf "$target"
    mv "$staging/$folder" "$target"
    rm -rf "$staging"
    trap - EXIT
done

if $RUN_INSTALL; then
    for folder in "${NAMES[@]}"; do
        if [[ -x "$DOTS_DIR/$folder/install.sh" ]]; then
            echo "==> running $folder/install.sh"
            (cd "$DOTS_DIR/$folder" && ./install.sh)
        else
            echo "==> $folder has no executable install.sh, skipping"
        fi
    done
fi

if $RELOAD; then
    echo "==> i3-msg reload"
    # Both entry paths reach here as the desktop user with DISPLAY set: from a
    # dom0 terminal it was inherited, over dev.Shell the re-exec above set it.
    DISPLAY="${DISPLAY:-:0}" i3-msg reload
fi

echo "==> done"
