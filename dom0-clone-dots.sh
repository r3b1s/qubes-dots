#!/usr/bin/env bash
# Run in dom0. Installs git in the "personal" AppVM, clones each URL in
# CLONE_TARS into /home/user/Dots there, then tar-copies that directory
# back into this dom0 user's home directory.
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
#   VM=personal; DOTS=/home/user/Dots; CLONE_TARS="https://github.com/you/repo1.git,git@github.com:you/repo2.git"; qvm-run --pass-io "$VM" "sudo dnf install -y git" && qvm-run --pass-io "$VM" "mkdir -p $DOTS" && IFS=',' read -ra U <<< "$CLONE_TARS" && for u in "${U[@]}"; do qvm-run --pass-io "$VM" "git -C $DOTS clone '$u'"; done && qvm-run --pass-io "$VM" "tar -cf - -C $(dirname "$DOTS") $(basename "$DOTS")" | tar -xf - -C "$HOME"

set -euo pipefail

VM=personal
DOTS_DIR=/home/user/Dots

if [[ -z "${CLONE_TARS:-}" ]]; then
    echo "error: CLONE_TARS must be set to a comma-separated list of git URLs" >&2
    exit 1
fi

# POSIX-sh-safe single-quote escaping for building remote command strings.
shquote() {
    printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

IFS=',' read -ra CLONE_URLS <<< "$CLONE_TARS"

echo "==> installing git in $VM"
qvm-run --pass-io "$VM" "sudo dnf install -y git"

echo "==> creating $DOTS_DIR in $VM"
qvm-run --pass-io "$VM" "mkdir -p $(shquote "$DOTS_DIR")"

for url in "${CLONE_URLS[@]}"; do
    url="$(echo "$url" | xargs)"
    [[ -z "$url" ]] && continue
    echo "==> cloning $url into $VM:$DOTS_DIR"
    qvm-run --pass-io "$VM" \
        "git -C $(shquote "$DOTS_DIR") clone $(shquote "$url")"
done

echo "==> copying $DOTS_DIR from $VM into dom0 \$HOME"
qvm-run --pass-io "$VM" \
    "tar -cf - -C $(shquote "$(dirname "$DOTS_DIR")") $(shquote "$(basename "$DOTS_DIR")")" \
    | tar -xf - -C "$HOME"

echo "==> done: $HOME/$(basename "$DOTS_DIR")"
