#!/bin/bash
#
# qubes-tpl-lolterm.sh — dom0 helper: provision the lolterm template
# (default: tpl-fedora-44-xfce-lolterm) standalone, without provisioning any
# qube that uses it. It is a clone of a base template (default: fedora-44-xfce)
# with lolterm's install-on-qubes.sh run inside it.
#
# VM provisioners that require this template (e.g. qubes-qubesdev-setup.sh)
# run this script themselves when the template is missing, so running it
# first is optional; run it on its own to build or refresh the template.
#
# Usage:
#   ./qubes-tpl-lolterm.sh
#   LOLTERM_REF=v1.2.3 ./qubes-tpl-lolterm.sh
#   LOLTERM_REINSTALL=1 ./qubes-tpl-lolterm.sh
#   ./qubes-tpl-lolterm.sh --help
#
# Variables (edit here or override via environment):
#   TEMPLATE_VM        lolterm template, cloned from BASE_TEMPLATE if missing
#                      (default: tpl-fedora-44-xfce-lolterm)
#   BASE_TEMPLATE      template to clone (default: fedora-44-xfce)
#   LOLTERM_REPO       lolterm git URL (default: https://github.com/r3b1s/lolterm.git)
#   LOLTERM_REF        branch or tag to install (default: main)
#   LOLTERM_FLAGS      install-on-qubes.sh flags (default: --mise --podman)
#   LOLTERM_GIT_NAME   optional, passed as --git-name
#   LOLTERM_GIT_EMAIL  optional, passed as --git-email
#   LOLTERM_REINSTALL  1 = run install-on-qubes.sh again on an existing
#                      TEMPLATE_VM (default: only right after cloning it)
#
# How it provisions:
#   dom0 only starts the template and sends it a short command; the template
#   clones lolterm itself through the Qubes updates proxy and stays offline
#   (no netvm). The template is shut down at the end so its root volume is
#   committed. Qubes already based on it pick the new root up at their next
#   start. lolterm puts per-user config in /etc/skel, which Qubes copies into
#   a qube's home only when the qube is created: an existing qube keeps its
#   home.
#
set -euo pipefail
umask 077
shopt -s inherit_errexit 2>/dev/null || true

TEMPLATE_VM="${TEMPLATE_VM:-tpl-fedora-44-xfce-lolterm}"
BASE_TEMPLATE="${BASE_TEMPLATE:-fedora-44-xfce}"
LOLTERM_REPO="${LOLTERM_REPO:-https://github.com/r3b1s/lolterm.git}"
LOLTERM_REF="${LOLTERM_REF:-main}"
LOLTERM_FLAGS="${LOLTERM_FLAGS:---mise --podman}"
LOLTERM_GIT_NAME="${LOLTERM_GIT_NAME:-}"
LOLTERM_GIT_EMAIL="${LOLTERM_GIT_EMAIL:-}"
LOLTERM_REINSTALL="${LOLTERM_REINSTALL:-0}"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  sed -n '2,38p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

# Dom0 tool check.
for _cmd in qvm-clone qvm-run qvm-shutdown qvm-check qvm-ls; do
  if ! command -v "$_cmd" >/dev/null 2>&1; then
    echo "ERROR: required tool not found in dom0: $_cmd" >&2
    exit 1
  fi
done
unset _cmd

qube_exists() { qvm-ls --raw-list | grep -qxF "$1"; }
qube_running() { qvm-check --quiet --running -- "$1" 2>/dev/null; }

# ---- Step 1: validate inputs ------------------------------------------------
echo "=> [1/2] Validating inputs ..."
if ! qube_exists "$TEMPLATE_VM" && ! qube_exists "$BASE_TEMPLATE"; then
  echo "ERROR: neither '$TEMPLATE_VM' nor its base '$BASE_TEMPLATE' exists." >&2
  exit 1
fi

# install-on-qubes.sh arguments, quoted for the shell inside the template.
read -r -a _flag_words <<<"$LOLTERM_FLAGS"
[ -n "$LOLTERM_GIT_NAME" ] && _flag_words+=(--git-name "$LOLTERM_GIT_NAME")
[ -n "$LOLTERM_GIT_EMAIL" ] && _flag_words+=(--git-email "$LOLTERM_GIT_EMAIL")
_install_args=
for _w in "${_flag_words[@]}"; do
  _install_args+=" $(printf '%q' "$_w")"
done
unset _w _flag_words

# ---- Step 2: clone and install lolterm --------------------------------------
_run_install=false
if qube_exists "$TEMPLATE_VM"; then
  echo "=> [2/2] Template '$TEMPLATE_VM' already exists."
  if [ "$LOLTERM_REINSTALL" = 1 ]; then
    _run_install=true
  else
    echo "   Not re-running lolterm (set LOLTERM_REINSTALL=1 to do so)."
  fi
else
  if qube_running "$BASE_TEMPLATE"; then
    echo "ERROR: '$BASE_TEMPLATE' is running; shut it down before cloning it." >&2
    exit 1
  fi
  echo "=> [2/2] Cloning '$BASE_TEMPLATE' -> '$TEMPLATE_VM' ..."
  qvm-clone "$BASE_TEMPLATE" "$TEMPLATE_VM"
  _run_install=true
fi

if $_run_install; then
  echo "=> [2/2] Installing lolterm ($LOLTERM_REF) in '$TEMPLATE_VM' via the updates proxy ..."
  qvm-run --pass-io -u root "$TEMPLATE_VM" -- bash -s <<EOF
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
if [ ! -e /var/run/qubes-service/updates-proxy-setup ]; then
    echo "ERROR: this template has no Qubes updates proxy (service updates-proxy-setup)." >&2
    exit 1
fi
export http_proxy=http://127.0.0.1:8082 https_proxy=http://127.0.0.1:8082
command -v git >/dev/null || dnf install -y git
src=\$(mktemp -d)
trap 'rm -rf "\$src"' EXIT
git clone --depth 1 --branch $(printf '%q' "$LOLTERM_REF") $(printf '%q' "$LOLTERM_REPO") "\$src"
LOLTERM_INSTALLER_DIR="\$src" bash "\$src/install-on-qubes.sh"$_install_args
command -v starship >/dev/null || { echo "ERROR: lolterm tools missing after install" >&2; exit 1; }
EOF
  echo "=> [2/2] Shutting down '$TEMPLATE_VM' to commit its root volume ..."
  qvm-shutdown --wait -- "$TEMPLATE_VM"
fi

echo
echo "===== Summary ====="
echo "  Template : $TEMPLATE_VM (clone of $BASE_TEMPLATE)"
if $_run_install; then
  echo "  lolterm  : $LOLTERM_REF ($_install_args) installed this run"
else
  echo "  lolterm  : already provisioned (LOLTERM_REINSTALL=1 to redo)"
fi
