#!/bin/sh
# Run in dom0. Installs kanata for the internal keyboard owned by dom0.
# Fetch/verify happens in personal; dom0 never downloads the release.
#
#   ./kanata/install-kanata-dom0.sh
#
# Does not touch sys-usb / sys-usb-dvm. For USB-path remapping see
# install-kanata-sys-usb.sh.
set -eu

KANATA_TAG=v1.12.0
KANATA_ZIP=linux-binaries-x64.zip
KANATA_ZIP_MEMBER=kanata_linux_x64
RELEASE_BASE="https://github.com/jtroo/kanata/releases/download/${KANATA_TAG}"

STAGE_VM=personal
STAGE_DIR=/home/user/kanata-stage

REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
PAYLOAD="$REPO/kanata"

usage() {
    sed -n '2,10p' "$0" | sed 's/^# \?//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        *) echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
    esac
done

die() { echo "error: $*" >&2; exit 1; }

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "need $1 (run this in dom0)"
}

vm_exists() {
    qvm-ls --raw-list | grep -qx "$1"
}

ensure_running() {
    qvm-check --running "$1" >/dev/null 2>&1 || qvm-start "$1"
}

for c in qvm-ls qvm-run qvm-start qvm-check; do
    need_cmd "$c"
done
command -v sudo >/dev/null 2>&1 || die "need sudo"

[ -f "$PAYLOAD/enthium.kbd" ] || die "missing $PAYLOAD/enthium.kbd"
[ -f "$PAYLOAD/kanata-dom0.service" ] || die "missing $PAYLOAD/kanata-dom0.service"
vm_exists "$STAGE_VM" || die "staging qube '$STAGE_VM' does not exist"

ensure_running "$STAGE_VM"

# --- download + verify in personal --------------------------------------------

echo "==> downloading kanata ${KANATA_TAG} in $STAGE_VM"
qvm-run --pass-io "$STAGE_VM" \
    "env STAGE_DIR='$STAGE_DIR' KANATA_ZIP='$KANATA_ZIP' \
         KANATA_ZIP_MEMBER='$KANATA_ZIP_MEMBER' RELEASE_BASE='$RELEASE_BASE' \
     sh -s" <<'REMOTE'
set -eu
mkdir -p "$STAGE_DIR"
cd "$STAGE_DIR"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL -O "$RELEASE_BASE/$KANATA_ZIP"
  curl -fsSL -O "$RELEASE_BASE/sha256sums"
elif command -v wget >/dev/null 2>&1; then
  wget -q "$RELEASE_BASE/$KANATA_ZIP"
  wget -q "$RELEASE_BASE/sha256sums"
else
  echo "error: need curl or wget" >&2
  exit 1
fi
grep " $KANATA_ZIP\$" sha256sums | sha256sum -c -
rm -rf extract
mkdir extract
if command -v unzip >/dev/null 2>&1; then
  unzip -o -d extract "$KANATA_ZIP"
else
  python3 - "$KANATA_ZIP" extract <<'PY'
import sys, zipfile
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
PY
fi
test -f "extract/$KANATA_ZIP_MEMBER"
cp -f "extract/$KANATA_ZIP_MEMBER" kanata
chmod +x kanata
echo "ok: $STAGE_DIR/kanata"
REMOTE

# --- install into dom0 --------------------------------------------------------

TMPBIN=$(mktemp)
trap 'rm -f "$TMPBIN"' EXIT
qvm-run --pass-io "$STAGE_VM" "cat $STAGE_DIR/kanata" >"$TMPBIN"
[ -s "$TMPBIN" ] || die "empty binary from $STAGE_VM"

echo "==> installing binary + layout + unit into dom0"
sudo install -d /etc/kanata
sudo install -m 755 "$TMPBIN" /usr/local/bin/kanata
sudo install -m 644 "$PAYLOAD/enthium.kbd" /etc/kanata/enthium.kbd
sudo install -m 644 "$PAYLOAD/kanata-dom0.service" /etc/systemd/system/kanata.service

echo "==> enabling kanata.service"
sudo systemctl daemon-reload
sudo systemctl enable --now kanata

echo
echo "Done. Internal keyboard remaps in dom0."
echo "  config: /etc/kanata/enthium.kbd"
echo "  binary: /usr/local/bin/kanata"
echo "  status: systemctl status kanata --no-pager"
echo "  stop:   sudo systemctl disable --now kanata"
