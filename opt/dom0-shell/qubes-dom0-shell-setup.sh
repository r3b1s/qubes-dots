#!/bin/bash
#
# qubes-dom0-shell-setup.sh — dom0 helper: install (or remove) the
# development-only mgmt.dev.Shell qrexec service and its policy, so one dev
# qube can open a dom0 shell over qrexec (no network listeners). See
# docs/qubes-shelling-into-dom0/method-1-qrexec-shell.md.
#
# Development machines only: the allowed qube gets full dom0 code execution.
#
# Usage (in dom0, from this directory's copy of the repo):
#   sudo ./qubes-dom0-shell-setup.sh            # install for qubesdev
#   sudo DEV_QUBE=dev-vm ./qubes-dom0-shell-setup.sh
#   sudo ./qubes-dom0-shell-setup.sh --remove   # revert to stock
#
# Installs, from the files next to this script:
#   mgmt.dev.Shell       -> /etc/qubes-rpc/mgmt.dev.Shell            (0755)
#   20-dev-shell.policy  -> /etc/qubes/policy.d/20-dev-shell.policy  (0644),
#                           with its source qube set to DEV_QUBE
#
# Then, from the dev qube:  qrexec-client-vm dom0 mgmt.dev.Shell
# No restart is needed: dom0 reads policy.d on every call.
#
set -euo pipefail
umask 022

DEV_QUBE="${DEV_QUBE:-qubesdev}"
SERVICE_DST=/etc/qubes-rpc/mgmt.dev.Shell
POLICY_DST=/etc/qubes/policy.d/20-dev-shell.policy
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

case "${1:-}" in
  -h|--help)
    sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
    ;;
  ""|--remove) ;;
  *) echo "Unknown option: $1 (use --help)" >&2; exit 1 ;;
esac

if [ ! -d /etc/qubes/policy.d ] || ! command -v qvm-ls >/dev/null 2>&1; then
  echo "ERROR: run this in dom0." >&2
  exit 1
fi
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: run with sudo; it writes to /etc/qubes-rpc and /etc/qubes/policy.d." >&2
  exit 1
fi

if [ "${1:-}" = --remove ]; then
  rm -f -- "$SERVICE_DST" "$POLICY_DST"
  echo "Removed $SERVICE_DST and $POLICY_DST; dom0 is back to stock."
  exit 0
fi

if ! printf '%s' "$DEV_QUBE" | grep -qE '^[A-Za-z][A-Za-z0-9_.-]*$'; then
  echo "ERROR: DEV_QUBE='$DEV_QUBE' is not a valid qube name." >&2
  exit 1
fi
if ! qvm-check --quiet -- "$DEV_QUBE" 2>/dev/null; then
  echo "WARNING: qube '$DEV_QUBE' does not exist yet; the policy applies once it does." >&2
fi

for f in mgmt.dev.Shell 20-dev-shell.policy; do
  [ -r "$SRC_DIR/$f" ] || { echo "ERROR: missing $SRC_DIR/$f" >&2; exit 1; }
done

# Policy with this run's source qube, linted before it reaches policy.d.
policy="$(mktemp)"
trap 'rm -f "$policy"' EXIT
sed -E "s/^(mgmt\.dev\.Shell[[:space:]]+\*[[:space:]]+)qubesdev([[:space:]])/\1${DEV_QUBE}\2/" \
  "$SRC_DIR/20-dev-shell.policy" > "$policy"
if ! grep -qE "^mgmt\.dev\.Shell[[:space:]]+\*[[:space:]]+${DEV_QUBE//./\\.}[[:space:]]+dom0[[:space:]]+allow$" "$policy"; then
  echo "ERROR: could not set the source qube in the policy file." >&2
  exit 1
fi
if command -v qubes-policy-lint >/dev/null 2>&1; then
  qubes-policy-lint -s "$policy"
fi

install -m 0755 -o root -g root "$SRC_DIR/mgmt.dev.Shell" "$SERVICE_DST"
install -m 0644 -o root -g root "$policy" "$POLICY_DST"

echo "Installed:"
echo "  $SERVICE_DST"
echo "  $POLICY_DST: $(grep -E '^mgmt\.dev\.Shell' "$POLICY_DST")"
echo
echo "From $DEV_QUBE:  qrexec-client-vm dom0 mgmt.dev.Shell"
echo "Revert:         sudo $0 --remove"
