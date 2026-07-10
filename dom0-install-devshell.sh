#!/bin/sh
# Run in dom0, once. Installs the dev.Shell qrexec service and a policy line
# granting <dev-vm> an unrestricted root shell in dom0.
#
# Get this repo into dom0 first with dom0-clone-dots.sh; dom0 has no network
# and never will, which is the point.
set -eu

SERVICE=/etc/qubes-rpc/dev.Shell
POLICY=/etc/qubes/policy.d/30-dev-shell.policy
REPO=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)

print_help() {
    cat <<'EOF'
Usage: ./dom0-install-devshell.sh <dev-vm> [--ask]
       ./dom0-install-devshell.sh --uninstall

Installs the dev.Shell qrexec service in dom0 and a policy granting <dev-vm>
a root shell there. Run in dom0.

Options:
  --ask        require a dom0 confirmation prompt on every call
  --uninstall  remove the service and policy
  -h, --help   show this help text and exit
EOF
}

case "${1:-}" in
    -h|--help)
        print_help
        exit 0
        ;;
    --uninstall)
        rm -f "$SERVICE" "$POLICY"
        echo "removed $SERVICE and $POLICY"
        exit 0
        ;;
    '')
        print_help >&2
        exit 1
        ;;
esac

DEV_VM=$1
shift

ACTION=allow
for arg in "$@"; do
    case "$arg" in
        --ask) ACTION=ask ;;
        *) echo "error: unknown argument: $arg" >&2; exit 1 ;;
    esac
done

# A policy naming a qube that does not exist never matches, which surfaces at
# the call site as a bare "Request refused" -- indistinguishable from a policy
# you got wrong. Fail here instead, where the name is visible.
if ! qvm-check --quiet "$DEV_VM" 2>/dev/null; then
    echo "error: no such qube: $DEV_VM" >&2
    exit 1
fi

if [ ! -f "$REPO/qrexec/dev.Shell" ]; then
    echo "error: $REPO/qrexec/dev.Shell not found" >&2
    exit 1
fi

install -m 0755 "$REPO/qrexec/dev.Shell" "$SERVICE"
echo "installed $SERVICE"

# Only the policy line ends in `allow`; the comments mentioning it do not.
sed -e "s|@DEV_VM@|$DEV_VM|" -e "s|allow\$|$ACTION|" \
    "$REPO/qrexec/30-dev-shell.policy" > "$POLICY"
chmod 0644 "$POLICY"
echo "installed $POLICY ($DEV_VM -> dom0, $ACTION)"

echo
echo "Test from $DEV_VM:"
echo "  echo 'qvm-ls --raw-data --fields NAME | head -3' | qrexec-client-vm dom0 dev.Shell"
