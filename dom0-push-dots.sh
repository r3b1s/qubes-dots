#!/usr/bin/env bash
# Run in dom0. Reverse of dom0-clone-dots.sh: tar-copies one or more
# directories out of this dom0 user's ~/Dots into /home/user/Dots on a
# target AppVM, then optionally runs `git push` in each of them there.
#
# Usage:
#   ./dom0-push-dots.sh <folder1,folder2,...> <target-vm> [--git-push]
#
# Arguments:
#   $1  comma-separated folder names, relative to ~/Dots
#   $2  target qube (AppVM) name
#   --git-push  after copying, cd into each copied folder on the target
#               VM and run a bare `git push`
#
# One-liner (paste into a dom0 terminal, edit FOLDERS/VM first):
#   FOLDERS="repo1,repo2"; VM=personal; qvm-run --pass-io "$VM" "mkdir -p /home/user/Dots" && IFS=',' read -ra F <<< "$FOLDERS" && for f in "${F[@]}"; do tar -cf - -C "$HOME/Dots" "$f" | qvm-run --pass-io "$VM" "tar -xf - -C /home/user/Dots"; done

set -euo pipefail

print_help() {
    cat <<'EOF'
Usage: ./dom0-push-dots.sh <folder1,folder2,...> <target-vm> [--git-push]

Run in dom0. Reverse of dom0-clone-dots.sh: tar-copies one or more
directories out of this dom0 user's ~/Dots into /home/user/Dots on a
target AppVM, then optionally runs `git push` in each of them there.

Arguments:
  folder1,folder2,...  comma-separated folder names, relative to ~/Dots
  target-vm             target qube (AppVM) name

Options:
  --git-push   after copying, cd into each copied folder on the target
               VM and run a bare `git push`
  -h, --help   show this help text and exit
EOF
}

case "${1:-}" in
    -h|--help)
        print_help
        exit 0
        ;;
esac

if [[ $# -lt 2 ]]; then
    echo "usage: $0 <folder1,folder2,...> <target-vm> [--git-push]" >&2
    exit 1
fi

FOLDERS_ARG=$1
TARGET_VM=$2
shift 2

GIT_PUSH=false
for arg in "$@"; do
    case "$arg" in
        --git-push) GIT_PUSH=true ;;
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

DOTS_DIR="$HOME/Dots"
REMOTE_DOTS_DIR=/home/user/Dots

# POSIX-sh-safe single-quote escaping for building remote command strings.
shquote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

IFS=',' read -ra FOLDERS <<< "$FOLDERS_ARG"

echo "==> creating $REMOTE_DOTS_DIR on $TARGET_VM"
qvm-run --pass-io "$TARGET_VM" "mkdir -p $(shquote "$REMOTE_DOTS_DIR")"

for folder in "${FOLDERS[@]}"; do
    folder="$(echo "$folder" | xargs)"
    [[ -z "$folder" ]] && continue

    if [[ ! -d "$DOTS_DIR/$folder" ]]; then
        echo "error: $DOTS_DIR/$folder does not exist" >&2
        exit 1
    fi

    echo "==> copying $folder into $TARGET_VM:$REMOTE_DOTS_DIR"
    tar -cf - -C "$DOTS_DIR" "$folder" \
        | qvm-run --pass-io "$TARGET_VM" "tar -xf - -C $(shquote "$REMOTE_DOTS_DIR")"
done

if $GIT_PUSH; then
    for folder in "${FOLDERS[@]}"; do
        folder="$(echo "$folder" | xargs)"
        [[ -z "$folder" ]] && continue

        echo "==> git push in $TARGET_VM:$REMOTE_DOTS_DIR/$folder"
        qvm-run --pass-io "$TARGET_VM" \
            "cd $(shquote "$REMOTE_DOTS_DIR/$folder") && git push"
    done
fi

echo "==> done"
