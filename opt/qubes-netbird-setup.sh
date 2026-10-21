#!/bin/bash
#
# qubes-netbird-setup.sh — dom0 helper: set up NetBird in Qubes OS using a
# Debian template, a DispVM template and a disposable service qube, per
# https://forum.qubes-os.org/t/netbird-setup/42139
#
# Usage:
#   ./qubes-netbird-setup.sh
#   NETBIRD_SETUP_KEY='...' ./qubes-netbird-setup.sh
#   NETBIRD_SETUP_KEY_FILE=/path/to/key ./qubes-netbird-setup.sh
#   ./qubes-netbird-setup.sh --help
#
# Variables (edit here or override via environment):
#   TEMPLATE_VM           base OS template to clone (default: debian-13-xfce)
#   DISPVM_TEMPL_NAME     DispVM template created by clone (default: tpl-netbird)
#   NETBIRD_VM_NAME       disposable qube running NetBird (default: sys-netbird)
#
# The setup key may come from:
#   - environment variable NETBIRD_SETUP_KEY
#   - first line of the file pointed to by NETBIRD_SETUP_KEY_FILE
# If empty, the script prints instructions for running `netbird up` yourself.
# NOTE: never hard-code the setup key into this file.
#
set -euo pipefail
umask 077
shopt -s inherit_errexit 2>/dev/null || true

TEMPLATE_VM="${TEMPLATE_VM:-debian-13-xfce}"
DISPVM_TEMPL_NAME="${DISPVM_TEMPL_NAME:-tpl-netbird}"
NETBIRD_VM_NAME="${NETBIRD_VM_NAME:-sys-netbird}"
NETBIRD_SETUP_KEY="${NETBIRD_SETUP_KEY:-}"
NETBIRD_SETUP_KEY_FILE="${NETBIRD_SETUP_KEY_FILE:-}"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

# Dom0 tool check.
for _cmd in qvm-clone qvm-create qvm-run qvm-prefs qvm-features qvm-shutdown qvm-ls bash; do
  if ! command -v "$_cmd" >/dev/null 2>&1; then
    echo "ERROR: required tool not found in dom0: $_cmd" >&2
    exit 1
  fi
done
unset _cmd

qube_exists() { qvm-ls --raw-list | grep -qxF "$1"; }

# ---- Step 13 prerequisite: resolve setup key (before printing key handling) --
if [ -z "$NETBIRD_SETUP_KEY" ] && [ -n "$NETBIRD_SETUP_KEY_FILE" ]; then
  if [ -r "$NETBIRD_SETUP_KEY_FILE" ]; then
    # first line only; file should contain just the key
    NETBIRD_SETUP_KEY=$(head -n 1 -- "$NETBIRD_SETUP_KEY_FILE")
  else
    echo "ERROR: NETBIRD_SETUP_KEY_FILE='$NETBIRD_SETUP_KEY_FILE' not readable" >&2
    exit 1
  fi
fi
# Never echo or write the key to stdout/logs.
if [ -n "$NETBIRD_SETUP_KEY" ]; then
  echo "=> Setup key found in environment/file (value not shown)."
else
  echo "=> No setup key provided (NETBIRD_SETUP_KEY / NETBIRD_SETUP_KEY_FILE empty)."
fi

# ---- Step 1: DispVM template ------------------------------------------------
if qube_exists "$DISPVM_TEMPL_NAME"; then
  _base=$(qvm-ls --raw-data "$DISPVM_TEMPL_NAME" | awk -F'|' '{print $4}')
  if [ "$_base" != "$TEMPLATE_VM" ]; then
    echo "ERROR: '$DISPVM_TEMPL_NAME' already exists but is based on '$_base', not '$TEMPLATE_VM'." >&2
    echo "Remove it first (qvm-remove --force-root $DISPVM_TEMPL_NAME) or set TEMPLATE_VM=$_base and rerun." >&2
    exit 1
  fi
  echo "=> [1/14] DispVM template '$DISPVM_TEMPL_NAME' already exists (based on '$_base'), reusing."
  unset _base
else
  echo "=> [1/14] Cloning template '$TEMPLATE_VM' -> '$DISPVM_TEMPL_NAME' as AppVM ..."
  # qvm-clone has no --template/--property argument. Converting a TemplateVM
  # source with --class AppVM leaves the new AppVM's template property at the
  # *system default template* (e.g. fedora-44-xfce), which is why apt-get
  # wasn't found. Pin it explicitly right after the clone.
  qvm-clone --class AppVM "$TEMPLATE_VM" "$DISPVM_TEMPL_NAME" --quiet
  qvm-prefs "$DISPVM_TEMPL_NAME" template "$TEMPLATE_VM"

  # A DispVM's template must be an AppVM with template_for_dispvms=True
  # (note plural). Error otherwise: "template for disposable (tpl-netbird)
  # needs to be an AppVM with template_for_dispvms=True".
  qvm-prefs "$DISPVM_TEMPL_NAME" template_for_dispvms true
fi

# ---- Step 2: disposable NetBird qube ---------------------------------------
if qube_exists "$NETBIRD_VM_NAME"; then
  echo "=> [2/14] Qube '$NETBIRD_VM_NAME' already exists, reusing."
else
  echo "=> [2/14] Creating disposable qube '$NETBIRD_VM_NAME' ..."
  qvm-create --disp --template "$DISPVM_TEMPL_NAME" "$NETBIRD_VM_NAME"
fi

# ---- Step 3: enable qubes-netbird-dns service flag -------------------------
# The Qubes service flag is `netbird-dns 1` via qvm-features; this makes the
# file /var/run/qubes-service/qubes-netbird-dns appear in the qube, which the
# unit's ConditionPathExists checks.
echo "=> [3/14] Enabling service flag netbird-dns on '$NETBIRD_VM_NAME' ..."
qvm-features "$NETBIRD_VM_NAME" netbird-dns 1

# ---- Step 4: install NetBird in the DispVM template ------------------------
echo "=> [4/14] Installing netbird packages in '$DISPVM_TEMPL_NAME' ..."
qvm-run --pass-io -u root "$DISPVM_TEMPL_NAME" -- bash -s <<'EOF'
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y curl ca-certificates gnupg jq
curl -sSL https://pkgs.netbird.io/debian/public.key | gpg --dearmor --output /usr/share/keyrings/netbird-archive-keyring.gpg
echo 'deb [signed-by=/usr/share/keyrings/netbird-archive-keyring.gpg] https://pkgs.netbird.io/debian stable main' | tee /etc/apt/sources.list.d/netbird.list
apt-get update
apt-get install -y netbird jq
systemctl enable netbird.service
EOF

# ---- Step 5: qubes-netbird-dns systemd unit --------------------------------
echo "=> [5/14] Writing /etc/systemd/system/qubes-netbird-dns.service in '$DISPVM_TEMPL_NAME' ..."
qvm-run --pass-io -u root "$DISPVM_TEMPL_NAME" -- bash -s <<'EOF'
set -euo pipefail
cat > /etc/systemd/system/qubes-netbird-dns.service <<'UNIT'
[Unit]
Description=NetBird DNS updater for Qubes
Requires=netbird.service
After=netbird.service
ConditionPathExists=/var/run/qubes-service/qubes-netbird-dns

[Service]
Type=oneshot
RemainAfterExit=yes
Restart=on-failure
ExecStart=/usr/bin/qubes-netbird-dns.sh start
ExecStop=/usr/bin/qubes-netbird-dns.sh stop

[Install]
WantedBy=multi-user.target
UNIT
chmod 0644 /etc/systemd/system/qubes-netbird-dns.service
EOF

# ---- Step 6: qubes-netbird-dns.sh helper (guide's script, bug fixed) -------
# The guide's script contains `if [ -z "netbird_dns" ]`, which is always true
# string; corrected to `-z "$netbird_dns"`.
echo "=> [6/14] Writing /usr/bin/qubes-netbird-dns.sh in '$DISPVM_TEMPL_NAME' ..."
qvm-run --pass-io -u root "$DISPVM_TEMPL_NAME" -- bash -s <<'EOF'
set -euo pipefail
cat > /usr/bin/qubes-netbird-dns.sh <<'HELPER'
#!/bin/bash
# Based on the Qubes forum guide's qubes-netbird-dns.sh
set -u

start() {
    netbird_dns=$(jq -r '.DNS' /var/lib/netbird/managed-state.json 2>/dev/null || true)
    # FIXED: original guide had `[ -z "netbird_dns" ]` (missing $)
    if [ -z "$netbird_dns" ] || [ "$netbird_dns" = "null" ]; then
        echo "No DNS from netbird state, skipped." >&2
        return 0
    fi
    sed -i "/netbird.*dns/d" /etc/resolv.conf
    echo "nameserver $netbird_dns #netbird dns" >> /etc/resolv.conf
}

stop() {
    sed -i "/netbird.*dns/d" /etc/resolv.conf
}

case "${1:-}" in
    start) start ;;
    stop)  stop ;;
    *)     echo "Usage: $0 {start|stop}" >&2; exit 1 ;;
esac
HELPER
chmod 0755 /usr/bin/qubes-netbird-dns.sh
EOF

# ---- Step 7: enable the unit in the template -------------------------------
echo "=> [7/14] Enabling qubes-netbird-dns.service in '$DISPVM_TEMPL_NAME' ..."
qvm-run --pass-io -u root "$DISPVM_TEMPL_NAME" -- bash -s <<'EOF'
set -euo pipefail
systemctl enable qubes-netbird-dns.service
EOF

# ---- Step 8: bind-dirs so NetBird state persists in dispvms ----------------
echo "=> [8/14] Configuring qubes bind-dirs for /var/{lib,log,cache}/netbird in '$DISPVM_TEMPL_NAME' ..."
qvm-run --pass-io -u root "$DISPVM_TEMPL_NAME" -- bash -s <<'EOF'
set -euo pipefail
mkdir -p /rw/bind-dirs/var/lib/netbird /rw/bind-dirs/var/log/netbird /rw/bind-dirs/var/cache/netbird
mkdir -p /rw/config/qubes-bind-dirs.d
cat > /rw/config/qubes-bind-dirs.d/50_netbird.conf <<'CONF'
binds+=( '/var/lib/netbird' '/var/log/netbird' '/var/cache/netbird' )
CONF
chmod 0644 /rw/config/qubes-bind-dirs.d/50_netbird.conf
EOF

# ---- Step 9: nftables leak-block rules (optional per guide, included) ------
echo "=> [9/14] Writing qubes-firewall-user-script (nftables leak block) in '$DISPVM_TEMPL_NAME' ..."
qvm-run --pass-io -u root "$DISPVM_TEMPL_NAME" -- bash -s <<'EOF'
set -euo pipefail
mkdir -p /rw/config
cat > /rw/config/qubes-firewall-user-script <<'NFT'
#!/bin/sh
nft add rule ip qubes custom-forward oifname eth0 counter drop
nft add rule ip6 qubes custom-forward oifname eth0 counter drop
NFT
chmod 0755 /rw/config/qubes-firewall-user-script
EOF

# ---- Step 10: shut down the DispVM template --------------------------------
echo "=> [10/14] Shutting down '$DISPVM_TEMPL_NAME' ..."
qvm-shutdown -- "$DISPVM_TEMPL_NAME"

# ---- Step 11: Provides network ---------------------------------------------
echo "=> [11/14] Enabling 'Provides network' on '$NETBIRD_VM_NAME' ..."
qvm-prefs "$NETBIRD_VM_NAME" provides_network true

# ---- Step 12: netbird.service enable (done in step 4; kept as a distinct
#      logical step for traceability with the guide) -------------------------

# ---- Step 13: run netbird up (setup key) ------------------------------------
echo "=> [13/14] Starting '$NETBIRD_VM_NAME' ..."
qvm-start --skip-if-running "$NETBIRD_VM_NAME"

if [ -n "$NETBIRD_SETUP_KEY" ]; then
  echo "=> [13/14] Enrolling '$NETBIRD_VM_NAME' into NetBird (key not shown) ..."
  # Disable xtrace so the key never appears in any log; pass via stdin env.
  qvm-run --pass-io -u root "$NETBIRD_VM_NAME" -- bash -s <<EOF
set +x
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
netbird up -s "${NETBIRD_SETUP_KEY}"
EOF
else
  echo "=> [13/14] No setup key supplied. Run this yourself inside the qube:"
  echo "       qvm-run \"$NETBIRD_VM_NAME\" term"
  echo "       then:  sudo netbird up -s <SETUP_KEY>   (or without -s to use a browser login)"
fi

echo "=> [12/14] (netbird.service already enabled in template during install)"

# ---- Step 14: summary -------------------------------------------------------
echo
echo "===== Summary ====="
echo "  DispVM template : $DISPVM_TEMPL_NAME (AppVM clone of $TEMPLATE_VM, template_for_dispvms=true)"
echo "  NetBird qube    : $NETBIRD_VM_NAME (disposable, providing network)"
echo
echo "Verify from the qube or dom0:"
echo "  qvm-run $NETBIRD_VM_NAME 'netbird status'"
echo
echo "The setup key was sourced from \$NETBIRD_SETUP_KEY / NETBIRD_SETUP_KEY_FILE."
echo "Nothing secret was stored in this script; do not hard-code keys in files."
