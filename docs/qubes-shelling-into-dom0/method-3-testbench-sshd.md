# Method 3 — the official test-bench: dom0 owns a NIC + sshd

This is **the upstream-sanctioned configuration** for a Qubes development
machine — `developer/debugging/test-bench.rst` in the qubes-doc clone,
written by the core team (woju) for exactly your use case: a spare machine
hosting an experimental dom0, driven over SSH from a dev VM, with the
core-admin test suite running on push. Quoting its notice:

> "This setup intentionally weakens some security properties in the testing
> system. So make sure you understand the risks and use exclusively for
> testing."

## What it changes

- The physical NIC is **removed from `sys-net`** and handed to dom0:
  dom0 gets a real DHCP address on your LAN.
- `openssh-server` runs in dom0 on that interface.
- Consequence: dom0 participates in L2. Your SSH attack surface is
  whatever that LAN can reach. Isolate accordingly — dedicated VLAN/spare
  switch with no route to the internet is the clean answer; the upstream
  doc assumes exactly this kind of private dev LAN (it gives the bench a
  static DHCP reservation).

## Setup (condensed from the upstream doc)

The upstream doc's NIC-handover script and systemd unit are
authoritative; the shape is:

1. In dom0, remove the NIC (PCI device) from `sys-net`, reboot.
2. Install packages: `sudo qubes-dom0-update dhcp-client openssh-server git`.
3. Save the NIC-binding script (`/home/user/bin/dom0_network.sh` — unbinds
   the NIC from the network driver, binds it to dom0's kernel driver, runs
   `dhclient`) and a oneshot `dom0-network-direct.service` to run it at
   boot. The doc's copy is in the qubes-doc clone;
   `BDF`/`DRIVER` variables must match your hardware (`lspci`).
4. `sudo systemctl enable --now sshd dom0-network-direct`.
5. Static DHCP reservation for the bench on your dev LAN.
6. From your dev machine/qube: `ssh-copy-id user@<bench-ip>`, key-only.

The upstream doc then builds the actual dev loop on top — worth following
verbatim:

- `qtb-install` — `scp` your built `qubes-core-dom0-*.rpm` to the bench,
  `ssh ... sudo rpm -i --replacepkgs --replacefiles` into the experimental
  dom0.
- `qtb-runtests` — `ssh testbench python -m qubes.tests.run`.
- `qtb-iterate` — build with `qubes-builder`, install, run tests: the
  commit→test loop as a single command.
- Git hooks: `pre-push` runs `qtb-iterate`, so nothing lands upstream
  untested. This is the piece that answers "the threat model keeps me from
  contributing": with a bench, contributions flow from your *dev* qube
  over SSH into a sacrificial dom0, and the daily-driver machine never
  weakens.

### dom0 software installs on a network-owning dom0

Upstream note, restated: once the only NIC belongs to dom0, the normal
`qubes-dom0-update` path changes — with the card detached from sys-net,
updates via the usual channel stop working, and you install with
`sudo dnf --setopt=reposdir=/etc/yum.repos.d install <pkg>` directly.
(If the machine has a second NIC, leave it in `sys-net` and keep the
supported update path for everything else.)

## When to choose this over methods 1–2

- You need dom0 **reboots** to be safe and unattended (the service unit
  reconnects the NIC at boot) — e.g. testing kernel/boot changes.
- You need real bandwidth into dom0 (RPM installs, ISO work) rather than
  stdio pipes.
- You want the loop the upstream devs actually run, with git hooks that
  keep your branches testable.

Exposure: dom0 is a first-class LAN host with an SSH daemon. On an
isolated dev VLAN that's a reasonable dev-lab posture; on any shared
network it's simply not.

## Revert

Remove the service unit, re-attach the PCI device to `sys-net` (Devices
widget or `qvm-pci`), reboot. dom0 returns to stock networking. Keep the
script/unit files in your dotfiles repo, not in dom0, so nothing lingers.
