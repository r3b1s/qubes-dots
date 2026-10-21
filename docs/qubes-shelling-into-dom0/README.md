# Shelling into dom0 — development-only patterns

> **Scope, stated plainly:** every technique here intentionally defeats part
> of the Qubes dom0 isolation model. dom0's security rests on having no
> network listeners and no untrusted input; each method below re-introduces
> one or both. This is acceptable **only** on a dedicated testing machine
> whose loss you can tolerate — never on a daily driver with real data.
> The upstream docs themselves bless this tradeoff for exactly this case:
> `developer/debugging/test-bench.rst` opens with *"This setup intentionally
> weakens some security properties in the testing system. So make sure you
> understand the risks and use exclusively for testing."*

The purpose here is upstream/Qubes development on a spare laptop: iterating
on `qubes-core-*` code, running the test suite, installing your own RPMs
into an experimental dom0 — work that is genuinely painful under the stock
constraints (dom0 update channel only, no network, terminal-only access).

## The four methods, ranked by exposure (least first)

| # | Method | dom0 exposes | Network change in dom0 | Grounded in |
|---|---|---|---|---|
| 1 | [qrexec shell service](method-1-qrexec-shell.md) | nothing — stdio over Xen vchan, policy-gated | **none** (no IP sockets at all) | qrexec docs ("VMs can call dom0 RPC targets") |
| 2 | [sshd + `qubes.ConnectTCP`](method-2-connecttcp-sshd.md) | sshd on the internal qubes network only | one package + socket unit | firewall.rst `qubes.ConnectTCP` recipes |
| 3 | [test-bench: dom0 owns a NIC + sshd](method-3-testbench-sshd.md) | sshd on a physical (ideally isolated) LAN | NIC moved out of sys-net into dom0 | **the official test-bench doc** |
| 4 | [remote access via mesh overlay](method-4-remote-mesh.md) | nothing new in dom0 — overlay client lives in an AppVM; traffic chains to #1 or #2 | none in dom0 | VPN service-qube pattern |

Rules that apply to all of them:

1. **Dedicated hardware.** The test machine holds no keys, no mail, no
   browser state. Reinstalling it is a non-event.
2. **Layer-2 isolation where possible.** Put the testbench on its own VLAN
   / spare switch with no route to anything but your dev machine.
3. **Key-only auth, no root login**, `AllowUsers` pinned. dom0's user is
   effectively root-equivalent already; don't compound it.
4. **Revert after the dev session** — every method is additive; see the
   revert block at the end of each file. Keep the added files in git
   *outside* the host so rollback is mechanical.
5. If you find yourself doing this on a machine that matters, stop and use
   the supported shape instead: run your tooling in a dev AppVM and drive
   the host through the [Admin API](../qubes-admin-api/automation.md) — a
   surprising share of "I need a dom0 shell" is really "I need `admin.*`
   calls", and that needs no dom0 exposure at all.

## Why a plain SSH daemon is not the first suggestion

Stock dom0 has no IP stack participation beyond the loopback-adjacent
internal plumbing: no DHCP client on a NIC (sys-net owns the NIC), no
listening services. Installing `openssh-server` is easy (`sudo
qubes-dom0-update openssh-server` — it's in the dom0 repo per the
test-bench doc), but the *reachability* question is what differentiates
the methods: vchan only (#1), internal 10.137.x network (#2), physical
LAN (#3), or remote-through-a-domU (#4).
