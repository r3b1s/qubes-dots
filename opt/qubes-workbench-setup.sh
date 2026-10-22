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
#   QUBE_PRIVATE_SIZE  private volume size; grown if smaller, never shrunk
#                      (default: 40G — Qubes' 2G default cannot hold the
#                      desktop build and hermes' tool store)
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
#   source, which is the slow part of a fresh install. Hermes ships no .desktop
#   file on Linux, and Qubes builds the Applications tab and app menu from
#   .desktop files, so this script writes
#   ~/.local/share/applications/hermes-desktop.desktop (home is on /rw, so it
#   survives the AppVM root reset). Reopen Settings → Applications, or press
#   Refresh Applications, to pick it up.
#
set -euo pipefail
umask 077
shopt -s inherit_errexit 2>/dev/null || true

QUBE_NAME="${QUBE_NAME:-workbench}"
TEMPLATE_VM="${TEMPLATE_VM:-tpl-fedora-44-xfce-lolterm}"
QUBE_USER="${QUBE_USER:-user}"
QUBE_LABEL="${QUBE_LABEL:-purple}"
QUBE_PRIVATE_SIZE="${QUBE_PRIVATE_SIZE:-40G}"
HERMES_CHANNEL="${HERMES_CHANNEL:-stable}"
HERMES_FLAGS="${HERMES_FLAGS:---include-desktop}"
HERMES_SYSTEM_PKGS="${HERMES_SYSTEM_PKGS:-git curl tar coreutils gcc gcc-c++ make python3 libatomic}"
HERMES_REINSTALL="${HERMES_REINSTALL:-0}"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  sed -n '2,53p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

# Dom0 tool check.
for _cmd in qvm-create qvm-run qvm-prefs qvm-shutdown qvm-check qvm-ls qvm-volume; do
  if ! command -v "$_cmd" >/dev/null 2>&1; then
    echo "ERROR: required tool not found in dom0: $_cmd" >&2
    exit 1
  fi
done
unset _cmd

qube_exists() { qvm-ls --raw-list | grep -qxF "$1"; }
qube_running() { qvm-check --quiet --running -- "$1" 2>/dev/null; }

# QUBE_PRIVATE_SIZE in bytes, matching qubesadmin.utils.parse_size: G/GB are
# decimal (40G = 40e9) and only Gi/GiB are binary. Plain digits are bytes.
_size_to_bytes() {
  local v num unit
  v=$(printf '%s' "$1" | tr -d '[:blank:]' | tr '[:lower:]' '[:upper:]')
  case "$v" in
    ''|*[!0-9]*)
      for unit in K KB M MB G GB KI KIB MI MIB GI GIB; do
        case "$v" in
          *"$unit")
            num="${v%"$unit"}"
            case "$num" in ''|*[!0-9]*) return 1 ;; esac
            case "$unit" in
              K|KB)    printf '%s' $(( num * 1000 )) ;;
              M|MB)    printf '%s' $(( num * 1000000 )) ;;
              G|GB)    printf '%s' $(( num * 1000000000 )) ;;
              KI|KIB)  printf '%s' $(( num * 1024 )) ;;
              MI|MIB)  printf '%s' $(( num * 1048576 )) ;;
              GI|GIB)  printf '%s' $(( num * 1073741824 )) ;;
            esac
            return 0 ;;
        esac
      done
      return 1 ;;
    *)
      printf '%s' "$v" ;;
  esac
}

# ---- Step 1: validate inputs ------------------------------------------------
echo "=> [1/6] Validating inputs ..."
case "$HERMES_CHANNEL" in
  stable|main) ;;
  *) echo "ERROR: HERMES_CHANNEL must be 'stable' or 'main', not '$HERMES_CHANNEL'." >&2; exit 1 ;;
esac
[ -n "$HERMES_SYSTEM_PKGS" ] || { echo "ERROR: HERMES_SYSTEM_PKGS is empty." >&2; exit 1; }
_want_bytes=$(_size_to_bytes "$QUBE_PRIVATE_SIZE") || {
  echo "ERROR: QUBE_PRIVATE_SIZE='$QUBE_PRIVATE_SIZE' is not a size (e.g. 40G)." >&2
  exit 1
}

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
  echo "=> [2/6] Template '$TEMPLATE_VM' already exists."
else
  echo "=> [2/6] Provisioning template '$TEMPLATE_VM' with $_tpl_script ..."
  TEMPLATE_VM="$TEMPLATE_VM" "$_tpl_script"
fi
unset _tpl_script

echo "=> [2/6] Ensuring hermes system packages in '$TEMPLATE_VM' ..."
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
  echo "=> [3/6] AppVM '$QUBE_NAME' already exists, reusing (its home is kept)."
  if qube_running "$QUBE_NAME"; then
    echo "   shutting down '$QUBE_NAME' ..."
    qvm-shutdown --wait -- "$QUBE_NAME"
  fi
  qvm-prefs "$QUBE_NAME" template "$TEMPLATE_VM"
else
  echo "=> [3/6] Creating AppVM '$QUBE_NAME' (template: $TEMPLATE_VM, label: $QUBE_LABEL) ..."
  qvm-create --template "$TEMPLATE_VM" --label "$QUBE_LABEL" "$QUBE_NAME"
fi

# An AppVM starts with a 2 GiB private volume, which the desktop build and
# hermes' tool store exhaust. Grow it (never shrink) while the qube is down.
if ! _cur_bytes=$(qvm-volume info "$QUBE_NAME:private" size) \
   || ! printf '%s' "$_cur_bytes" | grep -qE '^[0-9]+$'; then
  echo "ERROR: cannot read the private volume size of '$QUBE_NAME'." >&2
  exit 1
fi
if [ "$_cur_bytes" -lt "$_want_bytes" ]; then
  echo "=> [3/6] Growing private volume of '$QUBE_NAME' to $QUBE_PRIVATE_SIZE ..."
  qvm-volume resize "$QUBE_NAME:private" "$QUBE_PRIVATE_SIZE"
else
  echo "=> [3/6] Private volume of '$QUBE_NAME' is already at least $QUBE_PRIVATE_SIZE."
fi
unset _cur_bytes

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
  echo "=> [4/6] hermes already installed in '$QUBE_NAME'."
  echo "   Not running the installer (set HERMES_REINSTALL=1 to do so)."
else
  echo "=> [4/6] Installing hermes ($HERMES_CHANNEL) in '$QUBE_NAME' as '$QUBE_USER' ..."
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

# ---- Step 5: Qubes application entry ---------------------------------------
# Qubes builds the Applications tab and app menu from .desktop files, and
# hermes ships none on Linux. The entry goes in the user's home, which is on
# /rw, so it survives the AppVM root reset. Exec names the wrapper by absolute
# path because the Qubes launcher does not guarantee a login PATH.
if $_expect_desktop; then
  echo "=> [5/6] Writing the Hermes Desktop application entry ..."
  qvm-run --pass-io -u "$QUBE_USER" "$QUBE_NAME" -- bash -s <<EOF
set -euo pipefail
export HOME=\$(getent passwd "\$(id -un)" | cut -d: -f6)
apps="\$HOME/.local/share/applications"
mkdir -p "\$apps"
cat > "\$apps/hermes-desktop.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Hermes Desktop
Comment=Hermes Agent desktop
Exec=\$HOME/.local/bin/hermes desktop
Icon=\$HOME/.hermes/hermes-agent/apps/desktop/assets/icon.png
Terminal=false
Categories=Development;Utility;
StartupNotify=true
DESKTOP
chmod 0644 "\$apps/hermes-desktop.desktop"
EOF
else
  echo "=> [5/6] Desktop not requested; not writing an application entry."
fi

# ---- Step 6: verify ---------------------------------------------------------
echo "=> [6/6] Verifying hermes in '$QUBE_NAME' ..."
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
    entry="\$HOME/.local/share/applications/hermes-desktop.desktop"
    [ -f "\$entry" ] || fail "desktop entry missing: \$entry"
    grep -qx 'Exec=.*hermes desktop' "\$entry" || fail "desktop entry has no hermes Exec line"
    if [ -x /etc/qubes-rpc/qubes.GetAppmenus ]; then
        menus=\$(/etc/qubes-rpc/qubes.GetAppmenus 2>/dev/null || true)
        printf '%s\n' "\$menus" | grep -q 'hermes-desktop.desktop' \
            || fail "Qubes does not report hermes-desktop.desktop (entry not visible in Applications)"
    fi
fi
echo "Verification OK: \$version" >&2
EOF

echo
echo "===== Summary ====="
echo "  Template : $TEMPLATE_VM (lolterm)"
echo "  Qube     : $QUBE_NAME (AppVM)"
echo "  Storage  : private volume at least $QUBE_PRIVATE_SIZE"
if $_installed_this_run; then
  echo "  Hermes   : installed this run ($HERMES_CHANNEL) for '$QUBE_USER'"
else
  echo "  Hermes   : already installed for '$QUBE_USER'"
fi
if $_expect_desktop; then
  echo "  Desktop  : built from source (hermes desktop)"
  echo "  Menu     : ~/.local/share/applications/hermes-desktop.desktop"
else
  echo "  Desktop  : not requested"
fi
echo "  Log      : $QUBE_NAME:~/.hermes/logs/install.log"
