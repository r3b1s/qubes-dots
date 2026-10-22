#!/bin/bash
#
# qubes-workbench-setup.sh — dom0 helper: provision the `workbench` AppVM, a
# desktop qube based on the lolterm template, with Hermes Agent and Hermes
# Desktop installed for its default user.
#
# Usage:
#   ./qubes-workbench-setup.sh
#   HERMES_CHANNEL=main ./qubes-workbench-setup.sh
#   HERMES_FLAGS='--include-desktop --skip-browser' ./qubes-workbench-setup.sh
#   HERMES_REINSTALL=1 ./qubes-workbench-setup.sh
#   ./qubes-workbench-setup.sh --help
#
# Variables (edit here or override via environment):
#   QUBE_NAME          qube to create/reuse (default: workbench)
#   TEMPLATE_VM        lolterm template, provisioned by ./qubes-tpl-lolterm.sh
#                      if missing (default: tpl-fedora-44-xfce-lolterm)
#   QUBE_USER          account that owns the hermes install (default: user)
#   QUBE_LABEL         label for a newly created qube (default: purple)
#   HERMES_CHANNEL     install channel, stable or main (default: stable)
#   HERMES_FLAGS       install.sh flags; --non-interactive is always added
#                      (default: --include-desktop)
#   HERMES_SYSTEM_PKGS Fedora packages hermes needs at runtime and build time
#                      (default: git curl tar coreutils gcc gcc-c++ make
#                      python3 libatomic)
#   HERMES_REINSTALL   1 = run the hermes installer again on an existing
#                      install (default: only when hermes is missing)
#
# Template (lolterm):
#   TEMPLATE_VM is provisioned by ./qubes-tpl-lolterm.sh and this script runs
#   that provisioner when the template is missing. The AppVM's root filesystem
#   is rebuilt from the template at every boot, so hermes' system packages are
#   installed in the template, not in the qube: without that, Hermes' managed
#   Node.js (libatomic) and the desktop build would work only until the first
#   reboot. hermes itself lives in the qube's home, which is persistent.
#
# Hermes installation (unattended):
#   The installer runs as QUBE_USER with --non-interactive, which skips the
#   setup and gateway stages that need input. Its stdin is /dev/null so a stray
#   read cannot block, and dom0 runs it without a terminal, so the installer
#   streams child output instead of drawing status lines. sudo is never
#   prompted for: Qubes VMs have passwordless root, and the packages Hermes
#   needs (libatomic) are already in the template. The desktop is built from
#   source, which is the slow part of a fresh install.
#
set -euo pipefail
umask 077
shopt -s inherit_errexit 2>/dev/null || true

QUBE_NAME="${QUBE_NAME:-workbench}"
TEMPLATE_VM="${TEMPLATE_VM:-tpl-fedora-44-xfce-lolterm}"
QUBE_USER="${QUBE_USER:-user}"
QUBE_LABEL="${QUBE_LABEL:-purple}"
HERMES_CHANNEL="${HERMES_CHANNEL:-stable}"
HERMES_FLAGS="${HERMES_FLAGS:---include-desktop}"
HERMES_SYSTEM_PKGS="${HERMES_SYSTEM_PKGS:-git curl tar coreutils gcc gcc-c++ make python3 libatomic}"
HERMES_REINSTALL="${HERMES_REINSTALL:-0}"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

# Dom0 tool check.
for _cmd in qvm-create qvm-run qvm-prefs qvm-shutdown qvm-check qvm-ls; do
  if ! command -v "$_cmd" >/dev/null 2>&1; then
    echo "ERROR: required tool not found in dom0: $_cmd" >&2
    exit 1
  fi
done
unset _cmd

qube_exists() { qvm-ls --raw-list | grep -qxF "$1"; }
qube_running() { qvm-check --quiet --running -- "$1" 2>/dev/null; }

# ---- Step 1: validate inputs ------------------------------------------------
echo "=> [1/5] Validating inputs ..."
case "$HERMES_CHANNEL" in
  stable|main) ;;
  *) echo "ERROR: HERMES_CHANNEL must be 'stable' or 'main', not '$HERMES_CHANNEL'." >&2; exit 1 ;;
esac
[ -n "$HERMES_SYSTEM_PKGS" ] || { echo "ERROR: HERMES_SYSTEM_PKGS is empty." >&2; exit 1; }

# install.sh arguments, quoted for the shell inside the qube.
read -r -a _flag_words <<<"$HERMES_FLAGS"
_install_args=
for _w in "${_flag_words[@]}"; do
  _install_args+=" $(printf '%q' "$_w")"
done
unset _w _flag_words

_expect_desktop=false
case " $HERMES_FLAGS " in *" --include-desktop "*) _expect_desktop=true ;; esac

# ---- Step 2: template and its hermes prerequisites -------------------------
_tpl_script="$(cd -- "$(dirname -- "$0")" && pwd)/qubes-tpl-lolterm.sh"
[ -x "$_tpl_script" ] || { echo "ERROR: template provisioner not found: $_tpl_script" >&2; exit 1; }

if qube_exists "$TEMPLATE_VM"; then
  echo "=> [2/5] Template '$TEMPLATE_VM' already exists."
else
  echo "=> [2/5] Provisioning template '$TEMPLATE_VM' with $_tpl_script ..."
  TEMPLATE_VM="$TEMPLATE_VM" "$_tpl_script"
fi
unset _tpl_script

echo "=> [2/5] Ensuring hermes system packages in '$TEMPLATE_VM' ..."
if qube_exists "$QUBE_NAME" && qube_running "$QUBE_NAME"; then
  echo "   shutting down '$QUBE_NAME' so it picks up the template change ..."
  qvm-shutdown --wait -- "$QUBE_NAME"
fi
qvm-run --pass-io -u root "$TEMPLATE_VM" -- bash -s <<EOF
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
if [ ! -e /var/run/qubes-service/updates-proxy-setup ]; then
    echo "ERROR: this template has no Qubes updates proxy (service updates-proxy-setup)." >&2
    exit 1
fi
miss=
for p in $HERMES_SYSTEM_PKGS; do
    rpm -q "\$p" >/dev/null 2>&1 || miss="\$miss \$p"
done
if [ -n "\$miss" ]; then
    echo "   installing:\$miss" >&2
    dnf install -y \$miss
else
    echo "   all present" >&2
fi
EOF
if qube_running "$TEMPLATE_VM"; then
  echo "   shutting down '$TEMPLATE_VM' to commit its root volume ..."
  qvm-shutdown --wait -- "$TEMPLATE_VM"
fi

# ---- Step 3: create or reuse the qube -------------------------------------
if qube_exists "$QUBE_NAME"; then
  _cls=$(qvm-ls --raw-data --fields NAME,CLASS | awk -F'|' -v me="$QUBE_NAME" '$1 == me {print $2}')
  if [ "$_cls" != AppVM ]; then
    echo "ERROR: '$QUBE_NAME' exists but is a $_cls, not an AppVM." >&2
    exit 1
  fi
  unset _cls
  echo "=> [3/5] AppVM '$QUBE_NAME' already exists, reusing (its home is kept)."
  if qube_running "$QUBE_NAME"; then
    echo "   shutting down '$QUBE_NAME' ..."
    qvm-shutdown --wait -- "$QUBE_NAME"
  fi
  qvm-prefs "$QUBE_NAME" template "$TEMPLATE_VM"
else
  echo "=> [3/5] Creating AppVM '$QUBE_NAME' (template: $TEMPLATE_VM, label: $QUBE_LABEL) ..."
  qvm-create --template "$TEMPLATE_VM" --label "$QUBE_LABEL" "$QUBE_NAME"
fi

_netvm=$(qvm-prefs "$QUBE_NAME" netvm)
if [ -z "$_netvm" ] || [ "$_netvm" = None ]; then
  echo "ERROR: '$QUBE_NAME' has no net qube; the hermes installer needs network." >&2
  echo "       Assign one, e.g.: qvm-prefs $QUBE_NAME netvm sys-firewall" >&2
  exit 1
fi
unset _netvm

# ---- Step 4: hermes agent + desktop ----------------------------------------
_installed_this_run=false
if qvm-run --pass-io -u "$QUBE_USER" "$QUBE_NAME" -- bash -c 'h=$(getent passwd "$(id -un)" | cut -d: -f6); [ -x "$h/.local/bin/hermes" ]' 2>/dev/null; then
  _hermes_present=true
else
  _hermes_present=false
fi

if $_hermes_present && [ "$HERMES_REINSTALL" != 1 ]; then
  echo "=> [4/5] hermes already installed in '$QUBE_NAME'."
  echo "   Not running the installer (set HERMES_REINSTALL=1 to do so)."
else
  echo "=> [4/5] Installing hermes ($HERMES_CHANNEL) in '$QUBE_NAME' as '$QUBE_USER' ..."
  echo "   (--non-interactive; the desktop build runs from source and takes a while)"
  qvm-run --pass-io -u "$QUBE_USER" "$QUBE_NAME" -- bash -s <<EOF
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=\$(getent passwd "\$(id -un)" | cut -d: -f6)
src=\$(mktemp -d)
trap 'rm -rf "\$src"' EXIT
curl -fsSL https://hermes-agent.nousresearch.com/install.sh -o "\$src/install.sh"
bash "\$src/install.sh" --non-interactive --channel $(printf '%q' "$HERMES_CHANNEL")$_install_args </dev/null
EOF
  _installed_this_run=true
fi
unset _hermes_present

# ---- Step 5: verify ---------------------------------------------------------
echo "=> [5/5] Verifying hermes in '$QUBE_NAME' ..."
qvm-run --pass-io -u "$QUBE_USER" "$QUBE_NAME" -- bash -s <<EOF
set -euo pipefail
export HOME=\$(getent passwd "\$(id -un)" | cut -d: -f6)
export PATH="\$HOME/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
fail() { echo "ERROR: \$1" >&2; exit 1; }

[ -x "\$HOME/.local/bin/hermes" ] || fail "hermes launcher missing: \$HOME/.local/bin/hermes"
version=\$(hermes --version) || fail "hermes --version failed"
if [ '$_expect_desktop' = true ]; then
    [ -d "\$HOME/.hermes/hermes-agent/apps/desktop/release/linux-unpacked" ] \
        || fail "hermes desktop was not built"
fi
echo "Verification OK: \$version" >&2
EOF

echo
echo "===== Summary ====="
echo "  Template : $TEMPLATE_VM (lolterm)"
echo "  Qube     : $QUBE_NAME (AppVM)"
if $_installed_this_run; then
  echo "  Hermes   : installed this run ($HERMES_CHANNEL) for '$QUBE_USER'"
else
  echo "  Hermes   : already installed for '$QUBE_USER'"
fi
if $_expect_desktop; then
  echo "  Desktop  : built from source (hermes desktop)"
else
  echo "  Desktop  : not requested"
fi
echo "  Log      : $QUBE_NAME:~/.hermes/logs/install.log"
