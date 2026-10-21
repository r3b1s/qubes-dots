# Method 2 — sshd in dom0 reached via `qubes.ConnectTCP`

Exposes OpenSSH in dom0 **only on the internal qubes network
(10.137.0.0/16)**, with reachability provided by the documented
`qubes.ConnectTCP` qrexec service — no listening port on any physical
interface, nothing on your LAN. The remote end connects from a qube.

Grounded in `user/security-in-qubes/firewall.rst` ("Opening a single TCP
port to another network-isolated qube"), which shows exactly this
pattern for arbitrary TCP services between qubes.

## Setup

**1. Install and enable sshd in dom0:**

```console
[user @dom0 ~]$ sudo qubes-dom0-update openssh-server
[user @dom0 ~]$ sudo systemctl enable --now sshd
```

**2. Harden sshd** — dom0 user is root-equivalent, so pin it down:
`/etc/ssh/sshd_config` in dom0:

```
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
AllowUsers user
```

**3. Install your public key.** dom0 has no network, so transport the key
with the supported dom0 channel:

```console
[user @dev-vm ~]$ ssh-keygen -t ed25519
[user @dev-vm ~]$ qvm-copy-to-vm dom0 ~/.ssh/id_ed25519.pub
```

then in dom0 (landing zone is `~/QubesIncoming/dev-vm/`):

```console
[user @dom0 ~]$ mkdir -p ~/.ssh && chmod 700 ~/.ssh
[user @dom0 ~]$ cat ~/QubesIncoming/dev-vm/id_ed25519.pub >> ~/.ssh/authorized_keys
[user @dom0 ~]$ chmod 600 ~/.ssh/authorized_keys
[user @dom0 ~]$ rm -r ~/QubesIncoming/dev-vm/
```

**4. Allow the connection in policy** — `/etc/qubes/policy.d/20-dev-ssh.policy`:

```text
qubes.ConnectTCP +22 * dev-vm @default allow target=dom0
```

The `+22` argument scoping means only port 22 requests from `dev-vm` are
allowed; everything else implicit-denied.

## Use

From the dev qube:

```console
[user @dev-vm ~]$ qvm-connect-tcp 2222:@default:22
[user @dev-vm ~]$ ssh -p 2222 user@localhost
```

`qvm-connect-tcp` binds `localhost:2222` in `dev-vm` and tunnels each
connection over qrexec to dom0's port 22 — the policy line is what makes
`@default` resolve to dom0. Syntax follows the firewall doc exactly
(`localport:targetvm:remoteport`, `@default` = policy decides).

Add to `~/.ssh/config` in the dev qube for convenience:

```text
Host dom0-dev
    HostName localhost
    Port 2222
    User user
```

## Properties of this exposure

- sshd listens on dom0's internal address only; the stock routed+NAT'd
  qubes networking means no external host can address dom0 directly.
- Every connection traverses the policy engine — revoking the policy line
  cuts access without touching sshd.
- Still a network daemon in dom0: an OpenSSH 0-day reachable from any
  allowed qube is dom0-relevant. That's why this ranks below the qrexec
  shell, and why the allow-list must name your dev qube, not `*`.
- `qvm-connect-tcp` binding does not survive qube restarts; for a
  long-lived session, the firewall doc's systemd socket-unit pattern
  (`/rw/config/rc.local` + `Accept=true` socket) makes it permanent — but
  for dev use, re-running one command per session is the safer friction.

## Revert

```console
[user @dom0 ~]$ sudo systemctl disable --now sshd
[user @dom0 ~]$ rm /etc/qubes/policy.d/20-dev-ssh.policy
```

sshd can stay installed (inert when stopped); the policy removal is what
actually closes the path.
