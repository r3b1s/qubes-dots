#!/bin/sh
# Symlink dom0sh into place. Run in the *dev qube*, not dom0 — dom0sh is the
# caller side of the dev.Shell qrexec service, so it belongs on the qube that
# has network and tooling. Deliberately separate from install.sh, which
# installs the dots into dom0 and must not depend on this existing.
#
# The dom0 side is dom0-install-devshell.sh, run once in dom0.
#
# User-agnostic and safe to re-run; an existing non-symlink target is backed
# up, an existing symlink is replaced.
set -eu

REPO=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
DST="$HOME/.local/bin/dom0sh"

link() {
    src="$1"
    dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [ -e "$dst" ] && [ ! -L "$dst" ]; then
        backup="$dst.bak.$(date +%s)"
        mv "$dst" "$backup"
        echo "backed up $dst -> $backup"
    fi
    ln -sfn "$src" "$dst"
    echo "linked $dst -> $src"
}

if [ ! -x "$REPO/dom0sh" ]; then
    echo "error: $REPO/dom0sh not found or not executable" >&2
    exit 1
fi

# qrexec-client-vm is what dom0sh execs; its absence means this is dom0 (which
# has no such binary) or a qube with qubes-core-agent missing.
if ! command -v qrexec-client-vm >/dev/null 2>&1; then
    echo "error: qrexec-client-vm not found — run this in an AppVM, not dom0" >&2
    exit 1
fi

link "$REPO/dom0sh" "$DST"

case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) echo "note: $HOME/.local/bin is not on \$PATH" >&2 ;;
esac

echo
echo "Done. Install the dom0 side with dom0-install-devshell.sh, then test:"
echo "  dom0sh 'qvm-ls --raw-data --fields NAME | head -3'"
