#!/usr/bin/env bash
# Run in dom0. Installs git in the "personal" AppVM, clones each URL in
# CLONE_TARS into /home/user/Dotfiles there, then tar-copies that directory
# back into this dom0 user's home directory. A repo's existing clone in the
# AppVM is deleted first, so every run starts from a fresh clone.
#
# Usage:
#   CLONE_TARS="https://github.com/you/repo1.git,git@github.com:you/repo2.git" ./dom0-clone-dots.sh
#
# Note: `dnf install` inside an AppVM only persists for that VM's current
# run — the root filesystem resets to the TemplateVM's on next start. If
# you want git available permanently, install it in the template instead
# (`sudo qubes-dom0-update` doesn't apply here — use `qvm-run <template>
# 'sudo dnf install -y git'` or open a template terminal).
#
# One-liner (paste into a dom0 terminal, edit CLONE_TARS first):
#   VM=personal; DOTS=/home/user/Dotfiles; CLONE_TARS="https://github.com/you/repo1.git,git@github.com:you/repo2.git"; qvm-run --pass-io "$VM" "sudo dnf install -y git" && qvm-run --pass-io "$VM" "mkdir -p $DOTS" && IFS=',' read -ra U <<< "$CLONE_TARS" && for u in "${U[@]}"; do n=$(basename "${u%.git}"); qvm-run --pass-io "$VM" "rm -rf '$DOTS/$n' && git -C $DOTS clone '$u' '$n'"; done && qvm-run --pass-io "$VM" "tar -cf - -C $(dirname "$DOTS") $(basename "$DOTS")" | tar -xf - -C "$HOME"

set -euo pipefail

print_help() {
    cat <<'EOF'
Usage: CLONE_TARS="<url1,url2,...>" ./dom0-clone-dots.sh

Run in dom0. Installs git in the "personal" AppVM, clones each URL in
CLONE_TARS into /home/user/Dotfiles there, then tar-copies that directory
back into this dom0 user's home directory. A repo's existing clone in the
AppVM is deleted before it is cloned again.

Environment:
  CLONE_TARS   comma-separated list of git URLs (https or ssh) to clone

Options:
  -h, --help   show this help text and exit

Note: the git install only persists for this AppVM's current run — its
root filesystem resets to the TemplateVM's on next start.
EOF
}

case "${1:-}" in
    -h|--help)
        print_help
        exit 0
        ;;
esac

VM=personal
DOTS_DIR=/home/user/Dotfiles

if [[ -z "${CLONE_TARS:-}" ]]; then
    echo "error: CLONE_TARS must be set to a comma-separated list of git URLs" >&2
    exit 1
fi

# POSIX-sh-safe single-quote escaping for building remote command strings.
shquote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# Directory name git clone would pick for a URL: last path component (after
# '/' or ':'), without a trailing '/' or '.git'. Passed to git explicitly so
# the directory removed before cloning is exactly the one git creates.
clone_dir_name() {
    local name="${1%/}"
    name="${name%.git}"
    name="${name##*/}"
    name="${name##*:}"
    printf '%s' "$name"
}

IFS=',' read -ra CLONE_URLS <<< "$CLONE_TARS"

echo "==> installing git in $VM"
qvm-run --pass-io "$VM" "sudo dnf install -y git"

echo "==> creating $DOTS_DIR in $VM"
qvm-run --pass-io "$VM" "mkdir -p $(shquote "$DOTS_DIR")"

for url in "${CLONE_URLS[@]}"; do
    url="$(echo "$url" | xargs)"
    [[ -z "$url" ]] && continue
    name="$(clone_dir_name "$url")"
    if [[ -z "$name" || "$name" == "." || "$name" == ".." ]]; then
        echo "error: cannot derive a directory name from $url" >&2
        exit 1
    fi
    target="$DOTS_DIR/$name"
    echo "==> cloning $url into $VM:$target (replacing any existing clone)"
    qvm-run --pass-io "$VM" \
        "rm -rf -- $(shquote "$target") && git -C $(shquote "$DOTS_DIR") clone -- $(shquote "$url") $(shquote "$name")"
done

echo "==> copying $DOTS_DIR from $VM into dom0 \$HOME"
qvm-run --pass-io "$VM" \
    "tar -cf - -C $(shquote "$(dirname "$DOTS_DIR")") $(shquote "$(basename "$DOTS_DIR")")" \
    | tar -xf - -C "$HOME"

echo "==> done: $HOME/$(basename "$DOTS_DIR")"
