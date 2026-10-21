#!/bin/bash
#
# qubes-netbird-setup.sh — dom0 helper: set up NetBird in Qubes OS as a
# network-providing disposable service qube.
# Based on https://forum.qubes-os.org/t/netbird-setup/42139, adapted to the
# Qubes 4.2+/4.3 volume model.
#
# Usage:
#   ./qubes-netbird-setup.sh
#   NETBIRD_SETUP_KEY='...' ./qubes-netbird-setup.sh
#   NETBIRD_SETUP_KEY_FILE=/path/to/key ./qubes-netbird-setup.sh
#   ./qubes-netbird-setup.sh --help
#
# Variables (edit here or override via environment):
#   TEMPLATE_VM          base OS template to clone (default: debian-13-xfce)
#   NETBIRD_TEMPLATE     TemplateVM clone that holds the root-filesystem
#                        provisioning (packages, unit, helper script)
#                        (default: tpl-netbird)
#   DVM_TEMPL_NAME       AppVM disposable template holding /rw config
#                        (default: dvm-netbird)
#   NETBIRD_VM_NAME      named disposable qube running NetBird
#                        (default: sys-netbird)
#
# Why three qubes (Qubes volume model):
#   - TemplateVM root changes persist; AppVM root changes do NOT
#     (AppVM root = snap-on-start snapshot of its template, discarded at
#     shutdown). So packages and /etc, /usr files go in the TemplateVM.
#   - A DisposableVM's template must be an AppVM with
#     template_for_dispvms=True; only its /rw (private volume) is
#     customizable and inherited by spawned disposables. So /rw config
#     (bind-dirs, firewall script) goes in the AppVM dvm template.
#   - sys-netbird is the DispVM that actually runs netbird.
#
# The setup key may come from:
#   - environment variable NETBIRD_SETUP_KEY
#   - first line of the file pointed to by NETBIRD_SETUP_KEY_FILE
# If empty, the script prints instructions for running `netbird up` yourself.
# Enrollment always uses `netbird up --no-browser --setup-key ...` — key only,
# no SSO/browser flow (a browser inside sys-netbird halts provisioning). It
# must run as root (sudo) because of --allow-server-ssh, which the script
# already does via `qvm-run -u root`.
# NOTE: never hard-code the setup key into this file.
#
set -euo pipefail
umask 077
shopt -s inherit_errexit 2>/dev/null || true

TEMPLATE_VM="${TEMPLATE_VM:-debian-13-xfce}"
NETBIRD_TEMPLATE="${NETBIRD_TEMPLATE:-tpl-netbird}"
DVM_TEMPL_NAME="${DVM_TEMPL_NAME:-dvm-netbird}"
NETBIRD_VM_NAME="${NETBIRD_VM_NAME:-sys-netbird}"
NETBIRD_SETUP_KEY="${NETBIRD_SETUP_KEY:-}"
NETBIRD_SETUP_KEY_FILE="${NETBIRD_SETUP_KEY_FILE:-}"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  sed -n '2,44p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

# Dom0 tool check.
for _cmd in qvm-clone qvm-create qvm-run qvm-prefs qubes-prefs qvm-features qvm-shutdown qvm-start qvm-ls bash; do
  if ! command -v "$_cmd" >/dev/null 2>&1; then
    echo "ERROR: required tool not found in dom0: $_cmd" >&2
    exit 1
  fi
done
unset _cmd

qube_exists() { qvm-ls --raw-list | grep -qxF "$1"; }
vm_class() { qvm-ls --raw-data --fields=class "$1" | tail -n1; }

# Resolve setup key.
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

# ---- Step 1: TemplateVM clone (root-filesystem provisioning target) ---------
# qvm-clone preserves the class, so a clone of a TemplateVM is a TemplateVM
# again: its root volume is committed on shutdown (save_on_stop), unlike an
# AppVM's (snap_on_start, discarded). That is the whole point of this clone.
if qube_exists "$NETBIRD_TEMPLATE"; then
  echo "=> [1/7] TemplateVM '$NETBIRD_TEMPLATE' already exists, reusing."
else
  echo "=> [1/7] Cloning template '$TEMPLATE_VM' -> '$NETBIRD_TEMPLATE' ..."
  qvm-clone "$TEMPLATE_VM" "$NETBIRD_TEMPLATE"
fi

# ---- Step 2: provision root filesystem in the TemplateVM --------------------
# Packages, the DNS unit and the helper script live in /usr and /etc, i.e. on
# the root volume. They must be installed in a TemplateVM to survive its
# shutdown and reach tpl-derived qubes.

# Templates ship with netvm=None, so a fresh clone cannot reach package
# repos. Attach the same netvm the source template's default netvm chain
# (or the system default netvm) uses, instead of erroring.
_tpl_netvm=$(qvm-prefs "$NETBIRD_TEMPLATE" netvm)
if [ -z "$_tpl_netvm" ]; then
  _tpl_netvm=$(qubes-prefs default_netvm)
  echo "=> [2/7] Attaching '$NETBIRD_TEMPLATE' to default netvm: $_tpl_netvm"
  qvm-prefs "$NETBIRD_TEMPLATE" netvm "$_tpl_netvm"
fi
echo "=> [2/7] '$NETBIRD_TEMPLATE' netvm: $_tpl_netvm"
unset _tpl_netvm

echo "=> [2/7] Installing netbird packages + DNS unit in '$NETBIRD_TEMPLATE' ..."
qvm-run --pass-io -u root "$NETBIRD_TEMPLATE" -- bash -s <<'EOF'
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y curl ca-certificates gnupg jq
curl -sSL https://pkgs.netbird.io/debian/public.key | gpg --dearmor --output /usr/share/keyrings/netbird-archive-keyring.gpg
echo 'deb [signed-by=/usr/share/keyrings/netbird-archive-keyring.gpg] https://pkgs.netbird.io/debian stable main' | tee /etc/apt/sources.list.d/netbird.list
apt-get update
apt-get install -y netbird jq ufw

# DNS forwarding unit (per the Qubes forum guide).
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

# Helper: forward all DNS through the netbird internal IP.
# Compared with the guide's script: `[ -z "netbird_dns" ]` (missing $, always
# true) is fixed to `[ -z "$netbird_dns" ]`, and a null/empty jq result is
# guarded instead of producing "nameserver null".
cat > /usr/bin/qubes-netbird-dns.sh <<'HELPER'
#!/bin/bash
# Based on the Qubes forum guide's qubes-netbird-dns.sh
set -u

start() {
    netbird_dns=$(netbird status --json | jq -r '.netbirdIp' | cut -d'/' -f1)
    if [ -z "$netbird_dns" ] || [ "$netbird_dns" = "null" ]; then
        echo "Failed to get address from NetBird, cannot continue." >&2
        return 1
    fi
    primary_dns=$(/usr/bin/qubesdb-read /qubes-primary-dns 2>/dev/null || true)
    secondary_dns=$(/usr/bin/qubesdb-read /qubes-secondary-dns 2>/dev/null || true)
    if [ -z "$primary_dns" ] && [ -z "$secondary_dns" ]; then
        echo "No primary or secondary DNS servers configured, cannot continue." >&2
        return 1
    fi
    # Flush the current dnat-dns chain
    nft flush chain ip qubes dnat-dns
    for dns in $primary_dns $secondary_dns; do
        nft add rule ip qubes dnat-dns ip daddr "$dns" udp dport 53 dnat to "$netbird_dns"
        nft add rule ip qubes dnat-dns ip daddr "$dns" tcp dport 53 dnat to "$netbird_dns"
    done
    nft add rule ip qubes custom-input iifname == "vif*" udp dport 53 counter accept
    nft add rule ip qubes custom-input iifname == "vif*" tcp dport 53 counter accept
}

stop() {
    primary_dns=$(/usr/bin/qubesdb-read /qubes-primary-dns 2>/dev/null || true)
    secondary_dns=$(/usr/bin/qubesdb-read /qubes-secondary-dns 2>/dev/null || true)
    nft flush chain ip qubes dnat-dns
    for dns in $primary_dns $secondary_dns; do
        nft add rule ip qubes dnat-dns ip daddr "$dns" udp dport 53 dnat to "$dns"
        nft add rule ip qubes dnat-dns ip daddr "$dns" tcp dport 53 dnat to "$dns"
    done
    nft add rule ip qubes custom-input iifname == "vif*" udp dport 53 counter accept
    nft add rule ip qubes custom-input iifname == "vif*" tcp dport 53 counter accept
}

case "${1:-}" in
    start) start ;;
    stop)  stop ;;
    *)     echo "Usage: $0 {start|stop}" >&2; exit 1 ;;
esac
HELPER
chmod 0755 /usr/bin/qubes-netbird-dns.sh

systemctl enable netbird.service
systemctl enable ufw.service
systemctl enable qubes-netbird-dns.service
EOF

echo "=> [2/7] Shutting down '$NETBIRD_TEMPLATE' to commit root volume ..."
qvm-shutdown --wait -- "$NETBIRD_TEMPLATE"

# ---- Step 3: AppVM disposable template (inherits the TemplateVM root) -------
# Must be AppVM class with template_for_dispvms=True (Qubes requirement for
# DispVMs). Its /rw (private volume) is persistent and inherited by the
# disposables spawned from it — that is where /rw config goes.
if qube_exists "$DVM_TEMPL_NAME"; then
  echo "=> [3/7] Disposable template '$DVM_TEMPL_NAME' already exists, reusing."
else
  echo "=> [3/7] Creating disposable template '$DVM_TEMPL_NAME' (template: $NETBIRD_TEMPLATE) ..."
  qvm-create --template "$NETBIRD_TEMPLATE" --label black "$DVM_TEMPL_NAME"
fi
qvm-prefs "$DVM_TEMPL_NAME" template_for_dispvms true
qvm-features "$DVM_TEMPL_NAME" appmenus-dispvm 1

# ---- Step 4: /rw config in the AppVM disposable template --------------------
# /rw lives on the private volume, which is persistent for AppVMs and is what
# spawned disposables inherit. Bind-dirs makes the netbird state dirs survive
# DispVM restarts; the firewall script blocks leaks when the VPN is down.
echo "=> [4/7] Writing /rw config (bind-dirs + leak block) in '$DVM_TEMPL_NAME' ..."
qvm-run --pass-io -u root "$DVM_TEMPL_NAME" -- bash -s <<'EOF'
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
mkdir -p /rw/bind-dirs/var/lib/netbird /rw/bind-dirs/var/log/netbird /rw/bind-dirs/var/cache/netbird
mkdir -p /rw/config/qubes-bind-dirs.d
cat > /rw/config/qubes-bind-dirs.d/50_netbird.conf <<'CONF'
binds+=( '/var/lib/netbird' '/var/log/netbird' '/var/cache/netbird' )
CONF
chmod 0644 /rw/config/qubes-bind-dirs.d/50_netbird.conf

cat > /rw/config/rc.local <<'RCLOCAL'
#!/bin/bash
# Reapply the persistent ufw posture at every boot of every disposable
# spawned from this disposable template. Rules in /etc/ufw do NOT survive
# a DispVM restart (root volume is regenerated), so they must be re-run
# here each start.
set -u
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

ufw --force enable
# No SSH rule here at boot — /etc/ufw does not survive a DispVM restart, and
# we do NOT want a loose interface-only allow. The subnet-scoped rule is
# written back into this file by the provisioner (step 8) after netbird up
# has produced a wt0 lease; from then on every boot restores the tight rule.
ufw delete allow 22/tcp 2>/dev/null || true
ufw reload || ufw --force enable
RCLOCAL
chmod 0755 /rw/config/rc.local

cat > /rw/config/qubes-firewall-user-script <<'NFT'
#!/bin/sh
# Block traffic from being forwarded out eth0 when the VPN is down
# (leak protection, per the Qubes forum guide).
nft add rule ip qubes custom-forward oifname eth0 counter drop
nft add rule ip6 qubes custom-forward oifname eth0 counter drop
NFT
chmod 0755 /rw/config/qubes-firewall-user-script
EOF

echo "=> [4/7] Shutting down '$DVM_TEMPL_NAME' to commit /rw config ..."
qvm-shutdown --wait -- "$DVM_TEMPL_NAME"

# ---- Step 5: the disposable NetBird qube ------------------------------------
# Created only now, after both the template root and the dvm /rw are final.
if qube_exists "$NETBIRD_VM_NAME"; then
  echo "=> [5/7] Qube '$NETBIRD_VM_NAME' already exists, reusing."
else
  echo "=> [5/7] Creating disposable qube '$NETBIRD_VM_NAME' from '$DVM_TEMPL_NAME' ..."
  qvm-create --disp --template "$DVM_TEMPL_NAME" "$NETBIRD_VM_NAME"
fi

# Service flag for qubes-netbird-dns (makes /var/run/qubes-service/
# qubes-netbird-dns appear in the qube; the unit's ConditionPathExists
# checks for it).
qvm-features "$NETBIRD_VM_NAME" netbird-dns 1

# Provides network
echo "=> [5/7] Enabling 'Provides network' on '$NETBIRD_VM_NAME' ..."
qvm-prefs "$NETBIRD_VM_NAME" provides_network true

# ---- Step 6: start and enroll ------------------------------------------------
echo "=> [6/7] Starting '$NETBIRD_VM_NAME' ..."
qvm-start -- "$NETBIRD_VM_NAME"

if [ -n "$NETBIRD_SETUP_KEY" ]; then
  echo "=> [6/7] Enrolling '$NETBIRD_VM_NAME' into NetBird (key not shown) ..."
  # Disable xtrace so the key never appears in any log; pass via stdin env.
  qvm-run --pass-io -u root "$NETBIRD_VM_NAME" -- bash -s <<EOF
set +x
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
netbird up --no-browser --setup-key "${NETBIRD_SETUP_KEY}" \
  --wireguard-port 51821 \
  --disable-ssh-auth \
  --enable-ssh-local-port-forwarding \
  --enable-ssh-remote-port-forwarding \
  --enable-ssh-sftp \
  --enable-ssh-root \
  --allow-server-ssh
EOF
else
  echo "=> [6/7] No setup key supplied. Run this yourself inside the qube:"
  echo "       qvm-run \"$NETBIRD_VM_NAME\" term"
  echo "       then:  sudo netbird up --no-browser --setup-key <SETUP_KEY> \\"
  echo "         --wireguard-port 51821 --disable-ssh-auth --enable-ssh-local-port-forwarding \\"
  echo "         --enable-ssh-remote-port-forwarding --enable-ssh-sftp --enable-ssh-root --allow-server-ssh"
fi

# ---- Step 7: derive wt0 subnet post-enrollment ------------------------------
# wt0 appears only after netbird's daemon has connected; wait briefly, then
# print the subnet. The tight rule is applied in-session here but NOT yet
# persisted — persistence happens in step 8 by writing it back into rc.local.
echo "=> [7/7] Deriving wt0 subnet (post-enrollment) ..."
wt0_subnet=$(qvm-run --pass-io -u root "$NETBIRD_VM_NAME" -- bash -s <<'EOF'
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Wait briefly for the wt0 lease; it appears asynchronously after netbird up.
for _ in $(seq 1 15); do
    subnet=$(ip -4 -o addr show dev wt0 2>/dev/null | awk '{split($4,a,"/"); print a[1]"/"a[2]}' | head -n1)
    [ -n "$subnet" ] && { echo "$subnet"; exit 0; }
    sleep 2
done
echo "ERROR: wt0 has no IPv4 lease after 30s, cannot persist ufw SSH rule." >&2
exit 1
EOF
)

if [ -z "$wt0_subnet" ]; then
  echo "ERROR: wt0 subnet unavailable after netbird up." >&2
  exit 1
fi
echo "=> [7/7] wt0 subnet confirmed: $wt0_subnet"

# ---- Step 8: persist the tight rule into the dvm template's rc.local ---------
# /rw/config/rc.local in the dvm template is the boot-time source for every
# disposable spawned from it. sys-netbird must be shut down first because a
# dvm template's volumes are not writable while a dispvm from it is running
# (and the running instance holds a snapshot of /rw from its own start).

echo "=> [7/7] Shutting down '$NETBIRD_VM_NAME' so the dvm /rw is writable ..."
qvm-shutdown --wait -- "$NETBIRD_VM_NAME"

echo "=> [7/7] Rewriting rc.local in '$DVM_TEMPL_NAME' with the tight rule ..."
qvm-run --pass-io -u root "$DVM_TEMPL_NAME" -- bash -s <<EOF
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Idempotent: strip any previously persisted tight-rule block, then append
# the current one.
sed -i '/^# SSH scoped to the wt0 subnet discovered at provisioning time:/,+1d' /rw/config/rc.local
cat >> /rw/config/rc.local <<'BLOCK'

# SSH scoped to the wt0 subnet discovered at provisioning time: ${wt0_subnet}
ufw allow in on wt0 from '${wt0_subnet}' to any port 22 proto tcp
BLOCK

# Syntax check the resulting rc.local; refuse to leave a broken boot script.
bash -n /rw/config/rc.local
EOF

echo "=> [7/7] Tight rule persisted into '$DVM_TEMPL_NAME' rc.local; it becomes the boot-time rule on the next start."
echo "=> [7/7] Verifying the rule survives a reboot of '$NETBIRD_VM_NAME' ..."
qvm-start -- "$NETBIRD_VM_NAME"

# Assert rc.local actually produced the tight rule, and no looser variant.
qvm-run --pass-io -u root "$NETBIRD_VM_NAME" -- bash -s <<EOF
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Wait briefly for ufw/rc.local to have run and wt0 to come up (neither is
# instantaneous at boot).
inactive=1
for _ in \$(seq 1 15); do
    ufw status | grep -qw active && inactive=0 && break
    sleep 2
done
if [ "\$inactive" != 0 ]; then
    echo "ERROR: ufw did not become active after reboot." >&2
    exit 1
fi

rules=\$(ufw status | grep -c "22/tcp" || true)
if [ "\$rules" != 1 ]; then
    echo "Expected exactly one 22/tcp rule, found \$rules:" >&2
    ufw status >&2
    exit 1
fi
if ! ufw status | grep -q "in on wt0 from ${wt0_subnet} to any port 22"; then
    echo "Expected 22/tcp rule scoped to wt0 and subnet ${wt0_subnet}; not found:" >&2
    ufw status >&2
    exit 1
fi
# A loose interface-only rule must NOT be present.
if ufw status | grep -q "in on wt0 to any port 22"; then
    echo "ERROR: loose (subnet-less) 22/tcp allow found:" >&2
    ufw status >&2
    exit 1
fi
echo "Verification OK: exactly one 22/tcp rule, scoped to wt0 + ${wt0_subnet}."
EOF

echo
echo "===== Summary ====="
echo "  TemplateVM          : $NETBIRD_TEMPLATE (clone of $TEMPLATE_VM; holds packages + unit)"
echo "  Disposable template : $DVM_TEMPL_NAME (AppVM, template_for_dispvms=true; holds /rw config)"
echo "  NetBird qube        : $NETBIRD_VM_NAME (disposable, providing network)"
echo
echo "Verify from the qube or dom0:"
echo "  qvm-run $NETBIRD_VM_NAME -- 'netbird status'"
echo "  qvm-run $NETBIRD_VM_NAME -- 'systemctl status qubes-netbird-dns'"
echo
echo "The setup key was sourced from \$NETBIRD_SETUP_KEY / NETBIRD_SETUP_KEY_FILE."
echo "Nothing secret was stored in this script; do not hard-code keys in files."
