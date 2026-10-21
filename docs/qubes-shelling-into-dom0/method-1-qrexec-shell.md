# Method 1 — qrexec shell service (least exposure)

The only method that adds **zero** network listeners to dom0. A VM reaches
dom0 through qrexec — stdio multiplexed over Xen vchan — which is how dom0
already talks to every qube. No IP socket exists; there is nothing to
scan, nothing to route to, and the qrexec policy gates it like any other
RPC call.

## Idea

Qubes ships `qubes.VMShell` for VM→VM and dom0→VM command execution, and
the qrexec docs note that "VMs can call dom0 RPC targets". The stock
system does not ship a general dom0 shell service — so define one: a small
RPC service in dom0 that runs a shell for any caller the policy allows.

## Setup (in dom0)

**1. Create the service file** `/etc/qubes-rpc/mgmt.dev.Shell`:

```sh
#!/bin/sh
# Development-only dom0 shell service. Do not ship on a real system.
exec /bin/bash -l
```

`/etc/qubes-rpc/` is the standard location for dom0-side RPC service
definitions; each file is the program executed when the named service is
requested. Make it executable:

```console
[user @dom0 ~]$ chmod +x /etc/qubes-rpc/mgmt.dev.Shell
```

**2. Write the policy** `/etc/qubes/policy.d/20-dev-shell.policy`:

```text
mgmt.dev.Shell * dev-vm @default allow target=dom0
```

Scope it to your dev qube only (`dev-vm`), never `@anyvm`. First match
wins; everything else is implicitly denied.

**3. Restart the source qube's qrexec daemon** (policy is read
per-connection, but a running session caches):

```console
[user @dev-vm ~]$ systemctl --user restart qubes-qrexec-agent  # or reboot the qube
```

## Use

From the dev qube:

```console
[user @dev-vm ~]$ qrexec-client-vm dom0 mgmt.dev.Shell
[user @dev-vm ~]$ qvm-run -p dev-vm 'echo hi | qrexec-client-vm dom0 mgmt.dev.Shell'
```

Or through the Python client, which handles the socket plumbing:

```python
import qubesadmin
app = qubesadmin.Qubes()          # in dev-vm this is QubesRemote
proc = app.run_service('dom0', 'mgmt.dev.Shell')
```

Since the service's stdin/stdout is your pipe, anything works over it —
including an interactive shell (terminal emulation is raw; set `TERM`
manually) or `tar`/`rsync` over stdio for file transfer:

```console
[user @dev-vm ~]$ tar -C ~ -cf - my-repo | qrexec-client-vm dom0 mgmt.dev.Shell+untar
```

…with a matching untar variant in the service file. Note `qvm-run` itself
remains dom0→VM; VM→dom0 has no `qvm-run` equivalent — raw
`qrexec-client-vm` or `app.run_service` is the interface
([../qubes-admin-api/README.md](../qubes-admin-api/README.md)).

## What this does and doesn't weaken

- **Does not**: add IP listeners, change dom0's networking, put dom0 on
  any L2 segment. A remote attacker with no qube on the host gets nothing.
- **Does**: give the `dev-vm` qube full dom0 code execution, policy
  permitting. A compromised `dev-vm` = compromised dom0. That's the same
  tradeoff as every other method here — this one just confines the blast
  radius to qubes on the host.
- Compensating control: keep `dev-vm` minimal (no browser), and remove the
  policy file when not actively developing.

## Revert

```console
[user @dom0 ~]$ rm /etc/qubes-rpc/mgmt.dev.Shell /etc/qubes/policy.d/20-dev-shell.policy
```

dom0 is back to stock: no listeners, no added services, nothing
persistent.
