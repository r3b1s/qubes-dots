#!/bin/bash
#
# qubes-qubesdev-setup.sh — dom0 helper: provision the `qubesdev` AppVM, a
# lolterm development qube behind sys-netbird with a pinned IPv4 address, so it
# can be published as a NetBird Networks resource (<ip>/32, routing peer
# sys-netbird) that survives the qube being deleted and re-provisioned.
#
# Usage:
#   ./qubes-qubesdev-setup.sh
#   SSH_AUTHORIZED_KEYS_FILE=~/qubesdev.pub ./qubes-qubesdev-setup.sh
#   INGRESS_TCP_PORTS='8080' ./qubes-qubesdev-setup.sh
#   ./qubes-qubesdev-setup.sh --help
#
# Variables (edit here or override via environment):
#   QUBE_NAME          qube to create/reuse (default: qubesdev)
#   BASE_TEMPLATE      template to clone (default: fedora-44-xfce)
#   TEMPLATE_VM        lolterm template, cloned from BASE_TEMPLATE if missing
#                      (default: tpl-fedora-44-xfce-lolterm)
#   LOLTERM_REPO       lolterm git URL (default: https://github.com/r3b1s/lolterm.git)
#   LOLTERM_REF        branch or tag to install (default: main)
#   LOLTERM_FLAGS      install-on-qubes.sh flags (default: --mise --podman)
#   LOLTERM_GIT_NAME   optional, passed as --git-name
#   LOLTERM_GIT_EMAIL  optional, passed as --git-email
#   LOLTERM_REINSTALL  1 = run install-on-qubes.sh again on an existing
#                      TEMPLATE_VM (default: only right after cloning it)
#   QUBE_NETVM         its net qube (default: sys-netbird)
#   QUBE_IP            pinned IPv4 address (default: 10.137.100.10)
#   QUBE_LABEL         label for a newly created qube (default: purple)
#   INGRESS_TCP_PORTS  TCP ports to open to NetBird peers, space/comma
#                      separated (default: empty = open nothing)
#   INGRESS_FROM       source network allowed on those ports (default: the
#                      NetBird network sys-netbird stores in its
#                      vm-config.netbird-wt0-subnet feature)
#   SSH_AUTHORIZED_KEYS_FILE
#                      dom0 file of public keys (one per line, no options)
#                      to add for `user`. Adds 22 to the ingress ports for
#                      this run; pass it on every run that should keep 22 open
#
# Template (lolterm):
#   TEMPLATE_VM is a clone of BASE_TEMPLATE with lolterm's install-on-qubes.sh
#   run inside it. dom0 only starts the template and sends it a short command;
#   the template clones lolterm itself through the Qubes updates proxy and stays
#   offline (no netvm). lolterm puts per-user config in /etc/skel, which Qubes
#   copies into a qube's home only when the qube is created: a reused qube
#   keeps its existing home.
#
# Why the IP is pinned where it is:
#   Qubes derives an unset `ip` from the qube's qid (10.137.<hi>.<lo>), and
#   qids are capped at 10000, so automatic AppVM addresses never leave
#   10.137.0.1 - 10.137.39.94 (disposables use 10.138/16, DNS 10.139.1.x).
#   An address at 10.137.40.0 or above stays in the normal AppVM range but can
#   never be handed to another qube automatically. Setting `ip` explicitly
#   makes it independent of the qid, so re-provisioning reproduces it.
#
# Ingress (NetBird routing, Option A):
#   The qube's own Qubes input chain drops new inbound connections, so a
#   service reached through sys-netbird must be opened here as well as in the
#   NetBird access policy. A /rw/config/rc.local.d/50-netbird-ingress.rc hook
#   reads the ports and source from the qube's vm-config.* features at every
#   boot and adds one accept rule to custom-input. Without the features it
#   does nothing. To change the ports later, re-run this script or set the
#   features with qvm-features and restart the qube. The qube's gateway
#   (sys-netbird) is allowed too, which covers NetBird routes with masquerade
#   on.
#
# SSH:
#   lolterm installs sshd in the template but leaves it disabled. A
#   /rw/config/rc.local.d/40-sshd.rc hook starts it at boot only when `user`
#   has a non-empty authorized_keys. The qube's root filesystem is rebuilt
#   from the template at every boot, so the hook keeps state in /rw:
#     - the ed25519 host key lives in /rw/config/ssh and is copied into
#       /etc/ssh (and relabelled) each boot, so the fingerprint never changes
#     - the hardening drop-in /etc/ssh/sshd_config.d/10-qubesdev.conf is
#       rewritten each boot: key-only, no root login, AllowUsers user
#
set -euo pipefail
umask 077
shopt -s inherit_errexit 2>/dev/null || true

QUBE_NAME="${QUBE_NAME:-qubesdev}"
BASE_TEMPLATE="${BASE_TEMPLATE:-fedora-44-xfce}"
TEMPLATE_VM="${TEMPLATE_VM:-tpl-fedora-44-xfce-lolterm}"
LOLTERM_REPO="${LOLTERM_REPO:-https://github.com/r3b1s/lolterm.git}"
LOLTERM_REF="${LOLTERM_REF:-main}"
LOLTERM_FLAGS="${LOLTERM_FLAGS:---mise --podman}"
LOLTERM_GIT_NAME="${LOLTERM_GIT_NAME:-}"
LOLTERM_GIT_EMAIL="${LOLTERM_GIT_EMAIL:-}"
LOLTERM_REINSTALL="${LOLTERM_REINSTALL:-0}"
QUBE_NETVM="${QUBE_NETVM:-sys-netbird}"
QUBE_IP="${QUBE_IP:-10.137.100.10}"
QUBE_LABEL="${QUBE_LABEL:-purple}"
INGRESS_TCP_PORTS="${INGRESS_TCP_PORTS:-}"
INGRESS_FROM="${INGRESS_FROM:-}"
SSH_AUTHORIZED_KEYS_FILE="${SSH_AUTHORIZED_KEYS_FILE:-}"

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  sed -n '2,74p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
fi

# Dom0 tool check.
for _cmd in qvm-clone qvm-create qvm-run qvm-prefs qvm-features qvm-shutdown qvm-start qvm-check qvm-ls; do
  if ! command -v "$_cmd" >/dev/null 2>&1; then
    echo "ERROR: required tool not found in dom0: $_cmd" >&2
    exit 1
  fi
done
unset _cmd

qube_exists() { qvm-ls --raw-list | grep -qxF "$1"; }
qube_running() { qvm-check --quiet --running -- "$1" 2>/dev/null; }

# ---- Step 1: validate inputs ------------------------------------------------
echo "=> [1/6] Validating inputs ..."
if ! printf '%s' "$QUBE_IP" | grep -qE '^10\.137\.([0-9]{1,3})\.([0-9]{1,3})$'; then
  echo "ERROR: QUBE_IP='$QUBE_IP' must be in the Qubes AppVM range 10.137.0.0/16." >&2
  exit 1
fi
IFS=. read -r _ _ _ip_hi _ip_lo <<<"$QUBE_IP"
if [ "$_ip_hi" -gt 255 ] || [ "$_ip_lo" -gt 255 ] || [ "$_ip_lo" -eq 0 ] || [ "$_ip_lo" -eq 255 ]; then
  echo "ERROR: QUBE_IP='$QUBE_IP' is not a usable host address." >&2
  exit 1
fi
if [ "$_ip_hi" -lt 40 ]; then
  echo "WARNING: $QUBE_IP is inside the automatic range (10.137.0.1-10.137.39.94);" >&2
  echo "         a future qube may be assigned it. Prefer 10.137.40.0 or above." >&2
fi
unset _ip_hi _ip_lo

if ! qube_exists "$TEMPLATE_VM" && ! qube_exists "$BASE_TEMPLATE"; then
  echo "ERROR: neither '$TEMPLATE_VM' nor its base '$BASE_TEMPLATE' exists." >&2
  exit 1
fi
qube_exists "$QUBE_NETVM" || { echo "ERROR: net qube '$QUBE_NETVM' not found." >&2; exit 1; }
if [ "$(qvm-prefs "$QUBE_NETVM" provides_network)" != True ]; then
  echo "ERROR: '$QUBE_NETVM' does not provide network." >&2
  exit 1
fi

# Manually pinned addresses are not checked by Qubes, so check them here.
_clash=$(qvm-ls --raw-data --fields NAME,IP | awk -F'|' -v ip="$QUBE_IP" -v me="$QUBE_NAME" '$2 == ip && $1 != me {print $1}')
if [ -n "$_clash" ]; then
  echo "ERROR: $QUBE_IP is already used by: $_clash" >&2
  exit 1
fi
unset _clash

# Public keys: plain authorized_keys lines (no options). They are checked
# again with ssh-keygen inside the qube before being installed.
_keys=
if [ -n "$SSH_AUTHORIZED_KEYS_FILE" ]; then
  [ -r "$SSH_AUTHORIZED_KEYS_FILE" ] || { echo "ERROR: SSH_AUTHORIZED_KEYS_FILE not readable." >&2; exit 1; }
  _keys=$(grep -vE '^[[:space:]]*(#|$)' "$SSH_AUTHORIZED_KEYS_FILE" || true)
  [ -n "$_keys" ] || { echo "ERROR: no keys in SSH_AUTHORIZED_KEYS_FILE." >&2; exit 1; }
  if printf '%s\n' "$_keys" | grep -vqE '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com) [A-Za-z0-9+/]+={0,3}( [^[:cntrl:]]*)?$'; then
    echo "ERROR: SSH_AUTHORIZED_KEYS_FILE has a line that is not a plain public key." >&2
    exit 1
  fi
  INGRESS_TCP_PORTS="22 $INGRESS_TCP_PORTS"
fi

# Normalise the port list to "p1, p2" (deduplicated) and resolve the source.
_ports=
if [ -n "${INGRESS_TCP_PORTS// /}" ]; then
  for _p in $(printf '%s' "$INGRESS_TCP_PORTS" | tr ',' ' '); do
    if ! printf '%s' "$_p" | grep -qE '^[0-9]{1,5}$' || [ "$_p" -lt 1 ] || [ "$_p" -gt 65535 ]; then
      echo "ERROR: invalid port '$_p' in INGRESS_TCP_PORTS." >&2
      exit 1
    fi
    case ", $_ports, " in *", $_p, "*) continue ;; esac
    _ports="${_ports:+$_ports, }$_p"
  done
  unset _p
  if [ -z "$INGRESS_FROM" ]; then
    INGRESS_FROM=$(qvm-features "$QUBE_NETVM" vm-config.netbird-wt0-subnet 2>/dev/null || true)
  fi
  if [ -z "$INGRESS_FROM" ]; then
    echo "ERROR: ingress ports set but no source network: set INGRESS_FROM," >&2
    echo "       or provision '$QUBE_NETVM' so it carries vm-config.netbird-wt0-subnet." >&2
    exit 1
  fi
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

# ---- Step 2: lolterm template -----------------------------------------------
_run_install=false
if qube_exists "$TEMPLATE_VM"; then
  echo "=> [2/6] Template '$TEMPLATE_VM' already exists."
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
  echo "=> [2/6] Cloning '$BASE_TEMPLATE' -> '$TEMPLATE_VM' ..."
  qvm-clone "$BASE_TEMPLATE" "$TEMPLATE_VM"
  _run_install=true
fi

if $_run_install; then
  if qube_exists "$QUBE_NAME" && qube_running "$QUBE_NAME"; then
    echo "   shutting down '$QUBE_NAME' so it picks up the new template root ..."
    qvm-shutdown --wait -- "$QUBE_NAME"
  fi
  echo "=> [2/6] Installing lolterm ($LOLTERM_REF) in '$TEMPLATE_VM' via the updates proxy ..."
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
EOF
  echo "=> [2/6] Shutting down '$TEMPLATE_VM' to commit its root volume ..."
  qvm-shutdown --wait -- "$TEMPLATE_VM"
fi
unset _run_install

# ---- Step 3: create or reuse the qube -------------------------------------
# Properties below take effect at the next start, so make sure it is down.
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

# ---- Step 4: network settings ---------------------------------------------
echo "=> [4/6] netvm=$QUBE_NETVM, ip=$QUBE_IP ..."
qvm-prefs "$QUBE_NAME" netvm "$QUBE_NETVM"
qvm-prefs "$QUBE_NAME" ip "$QUBE_IP"

if [ -n "$_ports" ]; then
  echo "=> [4/6] Ingress: TCP { $_ports } from $INGRESS_FROM (+ gateway) ..."
  qvm-features "$QUBE_NAME" vm-config.netbird-ingress-tcp-ports "$_ports"
  qvm-features "$QUBE_NAME" vm-config.netbird-ingress-from "$INGRESS_FROM"
else
  echo "=> [4/6] Ingress: none (no INGRESS_TCP_PORTS or SSH keys)."
  qvm-features --unset "$QUBE_NAME" vm-config.netbird-ingress-tcp-ports 2>/dev/null || true
  qvm-features --unset "$QUBE_NAME" vm-config.netbird-ingress-from 2>/dev/null || true
fi

# ---- Step 5: boot hooks and keys in the qube's /rw ------------------------
# rc.local.d keeps them out of any rc.local the user maintains. AppVM /rw and
# /home are persistent, so this is written once; the features above and the
# presence of authorized_keys drive them.
echo "=> [5/6] Installing boot hooks in '$QUBE_NAME' (starts it and '$QUBE_NETVM') ..."
qvm-run --pass-io -u root "$QUBE_NAME" -- bash -s <<'EOF'
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
mkdir -p /rw/config/rc.local.d

cat > /rw/config/rc.local.d/50-netbird-ingress.rc <<'RC'
#!/bin/sh
# Managed by qubes-qubesdev-setup.sh (dom0). Opens the TCP ports listed in
# vm-config.netbird-ingress-tcp-ports to vm-config.netbird-ingress-from and to
# this qube's gateway (sys-netbird, for masqueraded NetBird routes). Without
# both features it does nothing, leaving Qubes' default inbound drop in place.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ports=$(qubesdb-read /vm-config/netbird-ingress-tcp-ports 2>/dev/null) || exit 0
from=$(qubesdb-read /vm-config/netbird-ingress-from 2>/dev/null) || exit 0
[ -n "$ports" ] && [ -n "$from" ] || exit 0
gw=$(qubesdb-read /qubes-gateway 2>/dev/null) || gw=
nft add rule ip qubes custom-input iifname "eth0" ip saddr "{ $from${gw:+, $gw} }" \
    tcp dport "{ $ports }" ct state new counter accept
RC
chmod 0755 /rw/config/rc.local.d/50-netbird-ingress.rc

cat > /rw/config/rc.local.d/40-sshd.rc <<'RC'
#!/bin/sh
# Managed by qubes-qubesdev-setup.sh (dom0). Starts sshd, key-only, when
# `user` has a non-empty authorized_keys. The root filesystem is rebuilt from
# the template at every boot, so the host key is kept in /rw/config/ssh and
# copied into /etc/ssh (relabelled for SELinux), and the drop-in is rewritten.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
home=$(getent passwd user | cut -d: -f6)
[ -s "$home/.ssh/authorized_keys" ] || exit 0
command -v sshd >/dev/null || { echo "40-sshd.rc: sshd not installed in the template" >&2; exit 0; }

state=/rw/config/ssh
key=ssh_host_ed25519_key
if [ ! -s "$state/$key" ]; then
    mkdir -p "$state"
    chmod 700 "$state"
    ssh-keygen -q -t ed25519 -N '' -C "$(hostname)" -f "$state/$key"
fi
install -m 600 -o root -g root "$state/$key" "/etc/ssh/$key"
install -m 644 -o root -g root "$state/$key.pub" "/etc/ssh/$key.pub"
restorecon -F "/etc/ssh/$key" "/etc/ssh/$key.pub" 2>/dev/null || true

mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/10-qubesdev.conf <<'CONF'
# Written at boot by /rw/config/rc.local.d/40-sshd.rc (qubes-qubesdev-setup.sh).
HostKey /etc/ssh/ssh_host_ed25519_key
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
AllowUsers user
CONF
chmod 644 /etc/ssh/sshd_config.d/10-qubesdev.conf
restorecon -F /etc/ssh/sshd_config.d/10-qubesdev.conf 2>/dev/null || true

sshd -t && systemctl start sshd.service
RC
chmod 0755 /rw/config/rc.local.d/40-sshd.rc
EOF

if [ -n "$_keys" ]; then
  echo "=> [5/6] Adding public keys for 'user' ..."
  printf '%s\n' "$_keys" | qvm-run --pass-io -u root "$QUBE_NAME" -- bash -c '
    set -euo pipefail
    home=$(getent passwd user | cut -d: -f6)
    new=$(mktemp)
    cat > "$new"
    ssh-keygen -l -f "$new" >/dev/null || { echo "ERROR: ssh-keygen rejected a key" >&2; exit 1; }
    install -d -m 700 -o user -g user "$home/.ssh"
    touch "$home/.ssh/authorized_keys"
    while IFS= read -r line; do
      grep -qxF "$line" "$home/.ssh/authorized_keys" || printf "%s\n" "$line" >> "$home/.ssh/authorized_keys"
    done < "$new"
    rm -f "$new"
    chown user:user "$home/.ssh/authorized_keys"
    chmod 600 "$home/.ssh/authorized_keys"
    restorecon -RF "$home/.ssh" 2>/dev/null || true
    echo "  $(grep -c . "$home/.ssh/authorized_keys") key(s) in authorized_keys"
  '
fi

# Restart so the pinned IP and the hooks are all live, then verify.
qvm-shutdown --wait -- "$QUBE_NAME"

# ---- Step 6: verify ---------------------------------------------------------
echo "=> [6/6] Starting '$QUBE_NAME' and verifying ..."
qvm-start --skip-if-running -- "$QUBE_NAME"
_fingerprint=$(qvm-run --pass-io -u root "$QUBE_NAME" -- bash -s <<EOF
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
fail() { echo "ERROR: \$1" >&2; exit 1; }

[ "\$(qubesdb-read /qubes-ip)" = '${QUBE_IP}' ] || fail "qubesdb /qubes-ip is not ${QUBE_IP}"
ip -4 -o addr show dev eth0 | grep -qF ' ${QUBE_IP}/' || fail "eth0 does not carry ${QUBE_IP}"
command -v starship >/dev/null || fail "lolterm tools missing (is the template '${TEMPLATE_VM}' provisioned?)"

if [ -n '${_ports}' ]; then
    for _ in \$(seq 1 10); do
        nft list chain ip qubes custom-input 2>/dev/null | grep -qF 'tcp dport' && break
        sleep 1
    done
    nft list chain ip qubes custom-input | grep -F 'iifname "eth0"' | grep -F 'ct state new' | grep -q 'accept' \
        || { nft list chain ip qubes custom-input >&2; fail "ingress accept rule missing"; }
fi

home=\$(getent passwd user | cut -d: -f6)
if [ -s "\$home/.ssh/authorized_keys" ]; then
    for _ in \$(seq 1 10); do
        systemctl is-active --quiet sshd.service && break
        sleep 1
    done
    systemctl is-active --quiet sshd.service || fail "sshd is not running"
    sshd -T | grep -qx 'passwordauthentication no' || fail "sshd allows passwords"
    sshd -T | grep -qx 'permitrootlogin no' || fail "sshd permits root login"
    sshd -T | grep -qx 'hostkey /etc/ssh/ssh_host_ed25519_key' || fail "sshd is not using the persistent host key"
    cmp -s /rw/config/ssh/ssh_host_ed25519_key /etc/ssh/ssh_host_ed25519_key || fail "host key does not match /rw copy"
    ssh-keygen -l -f /rw/config/ssh/ssh_host_ed25519_key.pub
fi
echo "Verification OK: eth0=${QUBE_IP}; ingress: ${_ports:-none}." >&2
EOF
)

echo
echo "===== Summary ====="
echo "  Template : $TEMPLATE_VM (clone of $BASE_TEMPLATE, lolterm $LOLTERM_REF)"
echo "  Qube     : $QUBE_NAME (AppVM)"
echo "  Net qube : $QUBE_NETVM"
echo "  IPv4     : $QUBE_IP  (pinned; NetBird Networks resource: $QUBE_IP/32, routing peer $QUBE_NETVM)"
if [ -n "$_ports" ]; then
  echo "  Ingress  : TCP { $_ports } from $INGRESS_FROM + gateway"
else
  echo "  Ingress  : none"
fi
if [ -n "$_fingerprint" ]; then
  echo "  SSH      : user@$QUBE_IP, host key $_fingerprint"
else
  echo "  SSH      : off (no authorized_keys for user)"
fi
