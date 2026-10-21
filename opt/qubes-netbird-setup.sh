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
#   DVM_TEMPL_NAME       AppVM disposable template holding /rw config AND
#                        the enrolled NetBird identity (default: dvm-netbird)
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
#     (bind-dirs, rc.local, firewall script) goes in the AppVM dvm template.
#   - sys-netbird is the DispVM that actually runs netbird. EVERYTHING it
#     writes, /rw and bind-dirs included, is discarded at shutdown: each
#     start is a fresh snapshot of the dvm template's last *committed* /rw.
#
# Consequences:
#   - Enrollment (`netbird up`) runs in the dvm template, not in
#     sys-netbird, so /var/lib/netbird (bind-dir'd into /rw) persists and
#     every sys-netbird boot comes up already logged in.
#   - The dvm template must be shut down after any /rw change, before
#     sys-netbird starts, or the change is not committed and not inherited.
#   - The dvm template and sys-netbird share one WireGuard identity: never
#     run them at the same time, and never spawn other disposables from it.
#
# The setup key may come from:
#   - environment variable NETBIRD_SETUP_KEY
#   - first line of the file pointed to by NETBIRD_SETUP_KEY_FILE
# If empty and the dvm template is not enrolled yet, the script prints
# instructions for running `netbird up` there yourself, then re-run it.
# Enrollment always uses `netbird up --no-browser --setup-key ...` — key only,
# no SSO/browser flow. It must run as root because of --allow-server-ssh,
# which the script already does via `qvm-run -u root`.
#
# SSH access control, in order of authority:
#   1. NetBird's own ACL (dashboard Access Control policy) is the real gate.
#      The client prepends `iifname "wt0" accept` to EVERY foreign nftables
#      chain on the input/forward hooks — Qubes' `ip qubes input` and
#      iptables-nft's `filter INPUT` (i.e. ufw) included — and re-inserts it
#      if removed, so rules in custom-input or ufw never see wt0 traffic.
#   2. Host-side guard: our own `inet netbird-ssh-guard` table drops SSH on
#      wt0 from anything outside the NetBird network, in a PREROUTING chain,
#      which NetBird does not touch. A drop in any base chain is final.
# NetBird's SSH server listens on 22022 and redirects 22 to it, so both
# ports are matched. The network is derived from wt0 after enrollment and
# handed to sys-netbird as the `vm-config.netbird-wt0-subnet` feature
# (qubesdb /vm-config/netbird-wt0-subnet), read by rc.local at every boot.
# ufw is deliberately NOT used: it would add a second ruleset NetBird
# bypasses on wt0, on top of Qubes' nftables tables, which cannot be removed.
#
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
  sed -n '2,70p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

# Dom0 tool check.
for _cmd in qvm-clone qvm-create qvm-run qvm-prefs qubes-prefs qvm-features qvm-service qvm-shutdown qvm-start qvm-check qvm-ls bash; do
  if ! command -v "$_cmd" >/dev/null 2>&1; then
    echo "ERROR: required tool not found in dom0: $_cmd" >&2
    exit 1
  fi
done
unset _cmd

qube_exists() { qvm-ls --raw-list | grep -qxF "$1"; }
qube_halt() {
  if qube_exists "$1" && qvm-check --quiet --running -- "$1" 2>/dev/null; then
    echo "   shutting down '$1' ..."
    qvm-shutdown --wait -- "$1"
  fi
}

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

# Re-runs: the disposable and its dvm template must be down so template and
# /rw changes are committed and picked up by the next sys-netbird start.
echo "=> [0/7] Stopping existing NetBird qubes (if running) ..."
qube_halt "$NETBIRD_VM_NAME"
qube_halt "$DVM_TEMPL_NAME"

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
# repos. Attach the system default netvm so provisioning can fetch packages.
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
curl -sSL https://pkgs.netbird.io/debian/public.key | gpg --batch --yes --dearmor --output /usr/share/keyrings/netbird-archive-keyring.gpg
echo 'deb [signed-by=/usr/share/keyrings/netbird-archive-keyring.gpg] https://pkgs.netbird.io/debian stable main' | tee /etc/apt/sources.list.d/netbird.list
apt-get update
apt-get install -y netbird jq

# DNS forwarding unit (per the Qubes forum guide). Gated on the Qubes
# service flag set with `qvm-service <qube> qubes-netbird-dns on`.
cat > /etc/systemd/system/qubes-netbird-dns.service <<'UNIT'
[Unit]
Description=NetBird DNS updater for Qubes
Requires=netbird.service
After=netbird.service
ConditionPathExists=/var/run/qubes-service/qubes-netbird-dns

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/qubes-netbird-dns.sh start
ExecStop=/usr/bin/qubes-netbird-dns.sh stop

[Install]
WantedBy=multi-user.target
UNIT
chmod 0644 /etc/systemd/system/qubes-netbird-dns.service

# Helper: forward all DNS through the netbird internal IP.
# Compared with the guide's script: `[ -z "netbird_dns" ]` (missing $, always
# true) is fixed to `[ -z "$netbird_dns" ]`, a null/empty jq result is
# guarded instead of producing "nameserver null", and start waits for the
# daemon to obtain its address (it is not up yet when netbird.service is).
cat > /usr/bin/qubes-netbird-dns.sh <<'HELPER'
#!/bin/bash
# Based on the Qubes forum guide's qubes-netbird-dns.sh
set -u

start() {
    netbird_dns=
    for _ in $(seq 1 60); do
        netbird_dns=$(netbird status --json 2>/dev/null | jq -r '.netbirdIp // empty' | cut -d'/' -f1)
        [ -n "$netbird_dns" ] && break
        sleep 2
    done
    if [ -z "$netbird_dns" ]; then
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
}

case "${1:-}" in
    start) start ;;
    stop)  stop ;;
    *)     echo "Usage: $0 {start|stop}" >&2; exit 1 ;;
esac
HELPER
chmod 0755 /usr/bin/qubes-netbird-dns.sh

# rc.local (run by qubes-misc-post.service) installs the SSH guard; start
# netbird only after it, so wt0 never comes up unguarded.
mkdir -p /etc/systemd/system/netbird.service.d
cat > /etc/systemd/system/netbird.service.d/10-qubes-order.conf <<'UNIT'
[Unit]
After=qubes-misc-post.service
UNIT
chmod 0644 /etc/systemd/system/netbird.service.d/10-qubes-order.conf

systemctl daemon-reload
systemctl enable netbird.service
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
# No app-menu disposables: each one would come up with sys-netbird's
# WireGuard identity and fight it for the same peer slot.
qvm-features --unset "$DVM_TEMPL_NAME" appmenus-dispvm 2>/dev/null || true

# ---- Step 4: /rw config in the AppVM disposable template --------------------
# /rw lives on the private volume, which is persistent for AppVMs and is what
# spawned disposables inherit. Bind-dirs keep the netbird state (profile,
# WireGuard key, login) on /rw, so enrolling the dvm template enrolls every
# sys-netbird boot. rc.local applies the nftables posture at each boot.
echo "=> [4/7] Writing /rw config (bind-dirs + rc.local + leak block) in '$DVM_TEMPL_NAME' ..."
qvm-run --pass-io -u root "$DVM_TEMPL_NAME" -- bash -s <<'EOF'
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
# Pre-created empty on purpose: bind-dirs copies the template's original
# content only when the /rw/bind-dirs path is missing, and the template's
# /var/lib/netbird may hold a profile the package's postinst generated.
mkdir -p /rw/bind-dirs/var/lib/netbird /rw/bind-dirs/var/log/netbird /rw/bind-dirs/var/cache/netbird
mkdir -p /rw/config/qubes-bind-dirs.d
cat > /rw/config/qubes-bind-dirs.d/50_netbird.conf <<'CONF'
binds+=( '/var/lib/netbird' '/var/log/netbird' '/var/cache/netbird' )
CONF
chmod 0644 /rw/config/qubes-bind-dirs.d/50_netbird.conf

cat > /rw/config/rc.local <<'RCLOCAL'
#!/bin/bash
# Reapply the persistent nftables posture at every boot of every disposable
# spawned from this disposable template. The Qubes tables (ip qubes) are
# regenerated on each start, so rules must be re-run here each boot.
#   1. Leak prevention: traffic must not leave via eth0 (VPN down => drop).
#   2. SSH guard: drop SSH on wt0 unless it comes from the NetBird network.
#      This lives in our own table on the PREROUTING hook because NetBird
#      prepends `iifname "wt0" accept` to every foreign input/forward chain
#      (Qubes' included), which would skip anything in custom-input. A drop
#      in any base chain is final, so this holds regardless. Both 22 and
#      NetBird's 22022 are matched. The network comes from the qube's
#      vm-config.netbird-wt0-subnet feature; without it (e.g. in the dvm
#      template itself) all SSH on wt0 is dropped.
# ufw is deliberately NOT used — NetBird bypasses it on wt0 the same way.
set -u
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 1) Leak prevention (forward path must go through wt0, not eth0).
nft add rule ip qubes custom-forward oifname eth0 counter drop
nft add rule ip6 qubes custom-forward oifname eth0 counter drop

# 2) SSH guard.
WT0_SUBNET=$(qubesdb-read /vm-config/netbird-wt0-subnet 2>/dev/null || true)
if [ -n "$WT0_SUBNET" ]; then
    v4_rule="iifname \"wt0\" ip saddr != $WT0_SUBNET tcp dport { 22, 22022 } counter drop"
else
    v4_rule="iifname \"wt0\" meta nfproto ipv4 tcp dport { 22, 22022 } counter drop"
fi
nft -f - <<NFT
table inet netbird-ssh-guard
delete table inet netbird-ssh-guard
table inet netbird-ssh-guard {
    chain prerouting {
        type filter hook prerouting priority mangle; policy accept;
        $v4_rule
        iifname "wt0" meta nfproto ipv6 tcp dport { 22, 22022 } counter drop
    }
}
NFT
RCLOCAL
chmod 0755 /rw/config/rc.local

cat > /rw/config/qubes-firewall-user-script <<'NFT'
#!/bin/sh
# Block traffic from being forwarded out eth0 when the VPN is down
# (leak prevention, per the Qubes forum guide). Kept as its own script so
# Qubes re-applies it on every firewall refresh, not just at boot.
nft add rule ip qubes custom-forward oifname eth0 counter drop
nft add rule ip6 qubes custom-forward oifname eth0 counter drop
NFT
chmod 0755 /rw/config/qubes-firewall-user-script
EOF

# Shut down so the bind-dirs config is active on the next boot (enrollment).
echo "=> [4/7] Shutting down '$DVM_TEMPL_NAME' to commit /rw config ..."
qvm-shutdown --wait -- "$DVM_TEMPL_NAME"

# ---- Step 5: the disposable NetBird qube ------------------------------------
if qube_exists "$NETBIRD_VM_NAME"; then
  echo "=> [5/7] Qube '$NETBIRD_VM_NAME' already exists, reusing."
else
  echo "=> [5/7] Creating disposable qube '$NETBIRD_VM_NAME' from '$DVM_TEMPL_NAME' ..."
  qvm-create --disp --template "$DVM_TEMPL_NAME" --label black "$NETBIRD_VM_NAME"
fi

# Service flag: makes /var/run/qubes-service/qubes-netbird-dns appear in the
# qube, which the unit's ConditionPathExists checks. A bare feature (no
# `service.` prefix) does not; drop the one older versions of this script set.
qvm-service "$NETBIRD_VM_NAME" qubes-netbird-dns on
qvm-features --unset "$NETBIRD_VM_NAME" netbird-dns 2>/dev/null || true

echo "=> [5/7] Enabling 'Provides network' on '$NETBIRD_VM_NAME' ..."
qvm-prefs "$NETBIRD_VM_NAME" provides_network true

# ---- Step 6: enroll the dvm template, persist the wt0 network ---------------
# Enrolling sys-netbird itself would be wasted: its /rw is discarded at
# shutdown. The dvm template's /rw/bind-dirs/var/lib/netbird is what every
# sys-netbird boot starts from.
echo "=> [6/7] Starting '$DVM_TEMPL_NAME' for enrollment ..."
qvm-start --skip-if-running -- "$DVM_TEMPL_NAME"

if [ -n "$NETBIRD_SETUP_KEY" ]; then
  echo "=> [6/7] Enrolling '$DVM_TEMPL_NAME' into NetBird (key not shown) ..."
  # Disable xtrace so the key never appears in any log; passed via stdin.
  qvm-run --pass-io -u root "$DVM_TEMPL_NAME" -- bash -s <<EOF
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
fi

# Derive the wt0 *network* (e.g. 100.92.0.0/16) from the interface address
# (e.g. 100.92.13.5/16). Works on re-runs without a key as long as the dvm
# template is already enrolled.
echo "=> [6/7] Deriving wt0 network in '$DVM_TEMPL_NAME' ..."
if ! wt0_subnet=$(qvm-run --pass-io -u root "$DVM_TEMPL_NAME" -- bash -s <<'EOF'
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
cidr=
for _ in $(seq 1 30); do
    cidr=$(ip -4 -o addr show dev wt0 2>/dev/null | awk '{print $4; exit}')
    [ -n "$cidr" ] && break
    sleep 2
done
[ -n "$cidr" ] || { echo "wt0 has no IPv4 address after 60s." >&2; exit 1; }
addr=${cidr%/*}; len=${cidr#*/}
IFS=. read -r a b c d <<<"$addr"
n=$(( ((a << 24) | (b << 16) | (c << 8) | d) & ((0xffffffff << (32 - len)) & 0xffffffff) ))
printf '%d.%d.%d.%d/%d\n' $((n >> 24 & 255)) $((n >> 16 & 255)) $((n >> 8 & 255)) $((n & 255)) "$len"
EOF
); then
  echo "ERROR: '$DVM_TEMPL_NAME' is not enrolled (no wt0 address)." >&2
  echo "       Enroll the dvm template (NOT $NETBIRD_VM_NAME), then re-run this script:" >&2
  echo "         qvm-run \"$DVM_TEMPL_NAME\" xterm" >&2
  echo "         sudo netbird up --no-browser --setup-key <SETUP_KEY> \\" >&2
  echo "           --wireguard-port 51821 --disable-ssh-auth --enable-ssh-local-port-forwarding \\" >&2
  echo "           --enable-ssh-remote-port-forwarding --enable-ssh-sftp --enable-ssh-root --allow-server-ssh" >&2
  exit 1
fi
echo "=> [6/7] wt0 network: $wt0_subnet"
# Per-qube value, not shared template state: exposed to sys-netbird as
# qubesdb /vm-config/netbird-wt0-subnet.
qvm-features "$NETBIRD_VM_NAME" vm-config.netbird-wt0-subnet "$wt0_subnet"

# The dvm template and sys-netbird share one identity, and the disposable
# only inherits /rw that has been committed — both require this shutdown.
echo "=> [6/7] Shutting down '$DVM_TEMPL_NAME' to commit enrollment ..."
qvm-shutdown --wait -- "$DVM_TEMPL_NAME"

# ---- Step 7: boot sys-netbird and verify it came up logged in and filtered -
echo "=> [7/7] Starting '$NETBIRD_VM_NAME' and verifying login + nft posture ..."
qvm-start --skip-if-running -- "$NETBIRD_VM_NAME"

qvm-run --pass-io -u root "$NETBIRD_VM_NAME" -- bash -s <<EOF
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
subnet='${wt0_subnet}'

# Login persisted: the daemon reconnects with the inherited profile.
connected=false
for _ in \$(seq 1 30); do
    connected=\$(netbird status --json 2>/dev/null | jq -r '.management.connected // false')
    [ "\$connected" = true ] && break
    sleep 2
done
if [ "\$connected" != true ]; then
    echo "ERROR: netbird is not connected to management after boot (login not persisted?):" >&2
    netbird status >&2 || true
    exit 1
fi

# rc.local has run (it is ordered after the Qubes firewall tables exist).
for _ in \$(seq 1 15); do
    nft list table inet netbird-ssh-guard >/dev/null 2>&1 && break
    sleep 2
done
guard=\$(nft list chain inet netbird-ssh-guard prerouting 2>/dev/null || true)
fwd=\$(nft list chain ip qubes custom-forward)

fail() { echo "ERROR: \$1" >&2; printf '%s\n%s\n' "\$guard" "\$fwd" >&2; exit 1; }

printf '%s\n' "\$fwd" | grep -q 'oifname "eth0".*drop' \
    || fail "eth0 leak drop missing from custom-forward"
[ -n "\$guard" ] || fail "SSH guard table inet netbird-ssh-guard missing"
printf '%s\n' "\$guard" | grep -F "ip saddr != \$subnet" | grep -F 'tcp dport { 22, 22022 }' | grep -q 'drop' \
    || fail "SSH guard does not drop non-\$subnet sources (vm-config.netbird-wt0-subnet not seen?)"
printf '%s\n' "\$guard" | grep -F 'nfproto ipv6' | grep -q 'drop' \
    || fail "SSH guard IPv6 drop missing"
# Informational: NetBird's injected wt0 accept is why the guard is not in custom-input.
if nft list chain ip qubes input 2>/dev/null | grep -q 'iifname "wt0".*accept'; then
    echo "note: NetBird has prepended a wt0 accept to ip qubes input (expected; the guard is unaffected)."
fi
echo "Verification OK: logged in; eth0 leak drop; SSH on wt0 dropped unless from \$subnet."
EOF

echo
echo "===== Summary ====="
echo "  TemplateVM          : $NETBIRD_TEMPLATE (clone of $TEMPLATE_VM; holds packages + unit)"
echo "  Disposable template : $DVM_TEMPL_NAME (AppVM, template_for_dispvms=true; holds /rw config + NetBird identity)"
echo "  NetBird qube        : $NETBIRD_VM_NAME (disposable, providing network)"
echo
echo "Verify from the qube or dom0:"
echo "  qvm-run --pass-io $NETBIRD_VM_NAME -- 'netbird status'"
echo "  qvm-run --pass-io $NETBIRD_VM_NAME -- 'systemctl status qubes-netbird-dns'"
echo
echo "Do not run $DVM_TEMPL_NAME while $NETBIRD_VM_NAME is up: they share one NetBird identity."
echo "The setup key was sourced from \$NETBIRD_SETUP_KEY / NETBIRD_SETUP_KEY_FILE."
echo "Nothing secret was stored in this script; do not hard-code keys in files."
