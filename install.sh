#!/bin/sh
# Symlink x11-dots into place. User-agnostic and safe to re-run; existing
# non-symlink targets are backed up, existing symlinks are replaced.
set -eu

REPO=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

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

link "$REPO/i3" "$HOME/.config/i3"
link "$REPO/dunst" "$HOME/.config/dunst"

for script in "$REPO"/bin/*; do
    link "$script" "$HOME/.local/bin/$(basename "$script")"
done

echo
echo "Done. Reload i3 with \$mod+Shift+Ctrl+Alt+c (or run: i3-msg reload)."
