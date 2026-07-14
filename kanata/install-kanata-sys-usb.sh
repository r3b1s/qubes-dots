#!/bin/sh
# Run in dom0. Stages kanata v1.12.0 into sys-usb-dvm via the personal qube,
# then points sys-usb at sys-usb-dvm (default-dvm is left untouched).
#
#   ./kanata/install-kanata-sys-usb.sh
#   ./kanata/install-kanata-sys-usb.sh --skip-template-switch   # stage only
#
# Network fetch happens only inside personal. Dom0 never downloads the release.
set -eu

KANATA_TAG=v1.12.0
KANATA_ZIP=linux-binaries-x64.zip
KANATA_ZIP_MEMBER=kanata_linux_x64
RELEASE_BASE="https://github.com/jtroo/kanata/releases/download/${KANATA_TAG}"

STAGE_VM=personal
BASE_DVM=default-dvm
USB_DVM=sys-usb-dvm
USB_VM=sys-usb
STAGE_DIR=/home/user/kanata-stage

REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
PAYLOAD="$REPO/kanata"
MARKER_BEGIN='# === kanata (qubes-dots) ==='
SWITCH_TEMPLATE=1

usage() {
    sed -n '2,8p' "$0" | sed 's/^# \?//'
}

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        --skip-template-switch) SWITCH_TEMPLATE=0; shift ;;
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

for c in qvm-ls qvm-run qvm-prefs qvm-start qvm-clone qvm-check; do
    need_cmd "$c"
done

[ -d "$PAYLOAD" ] || die "payload missing: $PAYLOAD"
[ -f "$PAYLOAD/enthium.kbd" ] || die "missing $PAYLOAD/enthium.kbd"
[ -f "$PAYLOAD/launch-input-sender.py" ] || die "missing launch-input-sender.py"
[ -f "$PAYLOAD/rc.local.snippet" ] || die "missing rc.local.snippet"

vm_exists "$STAGE_VM" || die "staging qube '$STAGE_VM' does not exist"

# --- ensure sys-usb-dvm (clone of default-dvm; leave default-dvm untouched) ---

if ! vm_exists "$USB_DVM"; then
    vm_exists "$BASE_DVM" || die "baseline disposable template '$BASE_DVM' does not exist"
    echo "==> cloning $BASE_DVM -> $USB_DVM (kanata overlay; $BASE_DVM left clean)"
    qvm-clone "$BASE_DVM" "$USB_DVM"
    # Clone inherits template_for_dispvms; re-assert in case prefs differ.
    qvm-prefs "$USB_DVM" template_for_dispvms True >/dev/null 2>&1 || true
else
    echo "==> using existing $USB_DVM"
    qvm-prefs "$USB_DVM" template_for_dispvms True >/dev/null 2>&1 || true
fi

ensure_running "$STAGE_VM"
ensure_running "$USB_DVM"

# --- download + verify in personal --------------------------------------------

echo "==> downloading kanata ${KANATA_TAG} in $STAGE_VM"

# Fetch/verify/extract entirely inside STAGE_VM (no network from dom0).
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

# --- copy payload + binary into sys-usb-dvm -----------------------------------

echo "==> installing payload into $USB_DVM:~/kanata"
qvm-run --pass-io "$USB_DVM" "mkdir -p /home/user/kanata"

tar -C "$PAYLOAD" -cf - \
    enthium.kbd \
    kanata.service \
    kanata-exclusions.conf \
    launch-input-sender.py \
    rc.local.snippet \
    README.md \
  | qvm-run --pass-io "$USB_DVM" "tar -C /home/user/kanata -xf -"

TMPBIN=$(mktemp)
trap 'rm -f "$TMPBIN"' EXIT
qvm-run --pass-io "$STAGE_VM" "cat $STAGE_DIR/kanata" >"$TMPBIN"
[ -s "$TMPBIN" ] || die "empty binary from $STAGE_VM"
# shellcheck disable=SC2002
cat "$TMPBIN" | qvm-run --pass-io "$USB_DVM" \
    "cat > /home/user/kanata/kanata && chmod +x /home/user/kanata/kanata /home/user/kanata/launch-input-sender.py"

# --- idempotent rc.local append -----------------------------------------------

echo "==> ensuring rc.local snippet in $USB_DVM"
if qvm-run --pass-io "$USB_DVM" \
    "grep -qxF '$MARKER_BEGIN' /rw/config/rc.local 2>/dev/null"; then
    echo "    already present"
else
    qvm-run --pass-io "$USB_DVM" \
        "sudo sh -c 'touch /rw/config/rc.local && chmod +x /rw/config/rc.local'"
    {
        echo
        cat "$PAYLOAD/rc.local.snippet"
    } | qvm-run --pass-io "$USB_DVM" "sudo tee -a /rw/config/rc.local >/dev/null"
    echo "    appended"
fi

echo "==> applying payload into $USB_DVM root (this boot)"
qvm-run --pass-io "$USB_DVM" "sudo sh /home/user/kanata/rc.local.snippet" || \
    echo "warn: live apply failed until sys-usb boots from this template; check logs" >&2

# --- point sys-usb at sys-usb-dvm ---------------------------------------------

PREV_TEMPLATE=
if vm_exists "$USB_VM"; then
    PREV_TEMPLATE=$(qvm-prefs "$USB_VM" template)
fi

echo
echo "Staging complete."
echo "  binary+config: $USB_DVM:/home/user/kanata/"
echo "  keyboard mute: KEYBOARDS=['0001:0001'] in launch-input-sender.py"
echo "  kanata grab:   linux-dev-names-include AT Translated Set 2 keyboard"
echo
echo "Revert if needed:"
echo "  qvm-shutdown --wait $USB_VM && qvm-prefs $USB_VM template ${PREV_TEMPLATE:-$BASE_DVM} && qvm-start $USB_VM"
echo

if [ "$SWITCH_TEMPLATE" -eq 0 ]; then
    echo "Skipping template switch (--skip-template-switch)."
    echo "  switch later: qvm-shutdown --wait $USB_VM && qvm-prefs $USB_VM template $USB_DVM && qvm-start $USB_VM"
    exit 0
fi

[ -n "$PREV_TEMPLATE" ] || die "$USB_VM does not exist; cannot switch template"
if [ "$PREV_TEMPLATE" = "$USB_DVM" ]; then
    echo "$USB_VM already uses template $USB_DVM"
    exit 0
fi

echo "WARNING: switching $USB_VM template can lock out the keyboard."
echo "Have a backup keyboard ready. $BASE_DVM is not modified."
printf "Type YES to switch %s template %s -> %s: " "$USB_VM" "$PREV_TEMPLATE" "$USB_DVM"
read -r ans
[ "$ans" = "YES" ] || die "aborted (answer was not YES)"

echo "==> switching $USB_VM template $PREV_TEMPLATE -> $USB_DVM"
qvm-shutdown --wait "$USB_VM"
qvm-prefs "$USB_VM" template "$USB_DVM"
qvm-start "$USB_VM"
echo "==> done. Verify: qvm-run --pass-io $USB_VM 'systemctl status kanata --no-pager'"
