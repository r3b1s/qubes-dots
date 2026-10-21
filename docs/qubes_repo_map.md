# Qubes OS repository map

Qubes OS's code lives as ~290 separate git repos under the
[QubesOS GitHub organization](https://github.com/QubesOS). Component layout
follows what the build system expects: each repo is a "component" with build
metadata at its root, fetched into `artifacts/sources` by
[qubes-builderv2](https://github.com/QubesOS/qubes-builderv2). The same
splitting is described upstream in the
[source-code doc](https://www.qubes-os.org/doc/source-code/) (see the local
qubes-doc clone at `developer/code/source-code.rst`).

This doc maps the repos by consequence: what makes the OS *be* Qubes is at the
top; packaging glue and conveniences are at the bottom. A few forks (upstream
software Qubes ships patches of) and operational repos are noted last.

## Tier 1 — Core system

The substrate: things that would make the machine "not Qubes" if removed.

| Repo | Role |
|---|---|
| [qubes-core-admin](https://github.com/QubesOS/qubes-core-admin) | **The heart.** qubesd: the daemon holding the VM database, VM lifecycle (create/start/clone), storage pools, and the policy engine. Runs in dom0. |
| [qubes-core-admin-client](https://github.com/QubesOS/qubes-core-admin-client) | The client side of the Admin API — `qvm-*` tools (`qvm-start`, `qvm-ls`, …) and the Python `qubesadmin` binding. How dom0 shells talk to qubesd. |
| [qubes-core-qrexec](https://github.com/QubesOS/qubes-core-qrexec) | qrexec: the inter-VM RPC system (`qubes.VMShell`, `admin.*`, custom `my.Service` calls). Policy enforcement, `qubes-rpc` client, agents on both dom0 and VM side. |
| [qubes-core-qubesdb](https://github.com/QubesOS/qubes-core-qubesdb) | QubesDB: the key/value database every VM mounts, used to feed configuration (netvm address, GUI settings, …) into running VMs. |
| [qubes-core-vchan-xen](https://github.com/QubesOS/qubes-core-vchan-xen) | libvchan: the low-level xenstore-based channel qrexec and other IPC ride on. |
| [qubes-core-agent-linux](https://github.com/QubesOS/qubes-core-agent-linux) | The in-VM side of everything above: qubesdb-daemon, qrexec agent, `/etc/qubes-rpc/*` service handlers (where `qubes.VMShell` lives), apt/pacman proxy config, misc qubes-* helpers. Installed in every Linux template. |
| [qubes-core-admin-linux](https://github.com/QubesOS/qubes-core-admin-linux) | dom0-side Linux glue: `qvm-block`, device handling, sys-audio/net plumbing that didn't fit the platform-neutral core. |
| [qubes-core-libvirt](https://github.com/QubesOS/qubes-core-libvirt) | Backend translating qubesd's needs into libvirt domain configs (libxl/Xen driver, Qubes-specific Xen/Fedora patches). |
| [qubes-vmm-xen](https://github.com/QubesOS/qubes-vmm-xen) | Qubes' Xen hypervisor fork — the VMM itself, with all Qubes security patches. (Newer work consolidates into [qubes-vmm-xen-unified](https://github.com/QubesOS/qubes-vmm-xen-unified); [xen](https://github.com/QubesOS/xen) is the upstream development fork.) |
| [qubes-linux-kernel](https://github.com/QubesOS/qubes-linux-kernel) | Dom0/Linux kernel with Qubes patches. |
| [qubes-installer-qubes-os](https://github.com/QubesOS/qubes-installer-qubes-os) | Anaconda-based ISO installer that lays down dom0. |

## Tier 2 — The VM interaction subsystems

What the user actually *sees* of a qube, each a self-contained protocol:

| Repo | Role |
|---|---|
| [qubes-gui-daemon](https://github.com/QubesOS/qubes-gui-daemon) + [qubes-gui-common](https://github.com/QubesOS/qubes-gui-common) | dom0 side of GUI virtualization: presents each VM's windows as local X windows, per-VM X server isolated via dom0 proxy. |
| [qubes-gui-agent-linux](https://github.com/QubesOS/qubes-gui-agent-linux) | In-VM GUI agent: window decoration copy, clipboard, fullscreen notification. ([qubes-gui-agent-wayland](https://github.com/QubesOS/qubes-gui-agent-wayland), [qubes-gui-rust](https://github.com/QubesOS/qubes-gui-rust) are the ongoing Rust/Wayland rework.) |
| [qubes-app-linux-input-proxy](https://github.com/QubesOS/qubes-app-linux-input-proxy) | Keyboard/mouse injection path from dom0 to VMs. |
| [qubes-app-linux-usb-proxy](https://github.com/QubesOS/qubes-app-linux-usb-proxy) | USBIP-over-qrexec proxy (device passthrough without trusting the VM). |
| [qubes-notification-proxy](https://github.com/QubesOS/qubes-notification-proxy) | dom0 notification channel for VMs (dunstify from a qube goes through here). |
| [qubes-remote-support](https://github.com/QubesOS/qubes-remote-support) | Support-share plumbing. |
| [qubes-app-linux-split-gpg](https://github.com/QubesOS/qubes-app-linux-split-gpg) | Split GPG/SSH: keys live in a vault VM; qrexec mediates signing/SSH
  operations. Repos: [split-gpg](https://github.com/QubesOS/qubes-app-linux-split-gpg),
  [split-gpg2](https://github.com/QubesOS/qubes-app-linux-split-gpg2),
  [split-ssh](https://github.com/QubesOS/qubes-app-linux-split-ssh), and
  [gpg-sign](https://github.com/QubesOS/qubes-app-linux-gpg-sign). |

## Tier 3 — dom0 desktop & management experience

| Repo | Role |
|---|---|
| [qubes-desktop-linux-common](https://github.com/QubesOS/qubes-desktop-linux-common) | Shared code behind dom0's Xfce integration (gui helpers, menu data). |
| [qubes-desktop-linux-manager](https://github.com/QubesOS/qubes-desktop-linux-manager) | Qubes Manager: the tray applet / device-attach UI. |
| [qubes-manager](https://github.com/QubesOS/qubes-manager) | The legacy Qt "Qubes Manager" window. |
| [qubes-desktop-linux-xfce4*](https://github.com/QubesOS/qubes-desktop-linux-xfce4) | Qubes' patched/componentized Xfce pieces (`-xfwm4`, `-garcon`, screensaver) plus equivalents for [KDE](https://github.com/QubesOS/qubes-desktop-linux-kde) and [i3](https://github.com/QubesOS/qubes-desktop-linux-i3) / [i3-settings-qubes](https://github.com/QubesOS/qubes-desktop-linux-i3-settings-qubes) (the source of our vendored `00-qubes-base.conf`), [awesome](https://github.com/QubesOS/qubes-desktop-linux-awesome), [xfdesktop](https://github.com/QubesOS/qubes-xfdesktop), [nautilus](https://github.com/QubesOS/qubes-nautilus). |
| [qubes-mgmt-salt-dom0-qvm](https://github.com/QubesOS/qubes-mgmt-salt-dom0-qvm) and the other `qubes-mgmt-salt-*` repos | Salt stacks invoked through the Admin API — `qubesctl` users and `qvm.*` state modules. The `qubes.*` syntax we see in docs (e.g. `qubes.VMShell`) is plain qrexec on top of `core-qrexec`; `qubesctl` is Sugar over the Admin API defined in core-admin(-client). |

## Tier 4 — Templates & app VMs

| Repo | Role |
|---|---|
| [qubes-linux-template-builder](https://github.com/QubesOS/qubes-linux-template-builder) | Scripts turning a base OS rootfs into a Qubes template. |
| [qubes-template-whonix](https://github.com/QubesOS/qubes-template-whonix), [qubes-template-configs](https://github.com/QubesOS/qubes-template-configs), [qubes-template-kicksecure](https://github.com/QubesOS/qubes-template-kicksecure) | Template build configs. |
| [qubes-gentoo](https://github.com/QubesOS/qubes-gentoo) | Gentoo template overlay. |
| [qubes-meta-packages](https://github.com/QubesOS/qubes-meta-packages) | Metapackage definitions pulling install sets together. |

## Tier 5 — Convenience apps (qrexec-heavy)

Mostly small daemons that exist purely to make a Qubes feature out of
something the base system already has. All are "appvm-side service +
dom0-side client + policy file" — the same shape as any custom
`my.Service`.

- [qubes-app-linux-tor](https://github.com/QubesOS/qubes-app-linux-tor) — integration control of Tor.
- [qubes-app-thunderbird](https://github.com/QubesOS/qubes-app-thunderbird) — isolated mail.
- [qubes-app-yubikey](https://github.com/QubesOS/qubes-app-yubikey) — YK setup helper.
- [qubes-app-u2f](https://github.com/QubesOS/qubes-app-u2f) — U2F proxy over qrexec.
- [qubes-app-linux-pdf-converter](https://github.com/QubesOS/qubes-app-linux-pdf-converter) / [qubes-app-linux-img-converter](https://github.com/QubesOS/qubes-app-linux-img-converter) — disposable qube trustedconverters.
- [qubes-app-linux-split-ssh](https://github.com/QubesOS/qubes-app-linux-split-ssh) and friends above.

## Tier 6 — Build, packaging & release machinery

| Repo | Role |
|---|---|
| [qubes-builderv2](https://github.com/QubesOS/qubes-builderv2) | The current build system (`./qb`). Per-distro plugins: [qubes-builder-rpm](https://github.com/QubesOS/qubes-builder-rpm), [qubes-builder-debian](https://github.com/QubesOS/qubes-builder-debian), [qubes-builder-archlinux](https://github.com/QubesOS/qubes-builder-archlinux), [qubes-builder-gentoo](https://github.com/QubesOS/qubes-builder-gentoo), [qubes-builder-windows](https://github.com/QubesOS/qubes-builder-windows) (+ `-cross`). Old v1 lives in [qubes-builder](https://github.com/QubesOS/qubes-builder). |
| [qubes-release-configs](https://github.com/QubesOS/qubes-release-configs) | Which components/templates make up a given release. |
| [qubes-continuous-integration](https://github.com/QubesOS/qubes-continuous-integration) + [openqa-tests-qubesos](https://github.com/QubesOS/openqa-tests-qubesos) | CI and system-level test harness. |
| `qubes-<upstream-pkg>` repos ([qubes-rpm](https://github.com/QubesOS/qubes-rpm), qubes-dnf, qubes-libdnf, qubes-alsa-lib, qubes-grub2, qubes-libvirt-adjacent, qubes-lvm2, qubes-zfs, qubes-openssl-compatible, qubes-openssh, qubes-librepo, qubes-libsolv, …) | Qubes' forks/patches of upstream packages they ship but need to fix. These are *build components*, not Qubes logic. |
| [qubes-linux-utils](https://github.com/QubesOS/qubes-linux-utils) | misc dom0+VM utilities. |

## Tier 7 — Docs, website, security process

| Repo | Role |
|---|---|
| [qubes-doc](https://github.com/QubesOS/qubes-doc) | Canonical documentation (RST under `user/`, `developer/`). We have this cloned locally at `~/3rdParty/qubes-doc`. |
| [qubes-offline-doc](https://github.com/QubesOS/qubes-offline-doc) | Docs shipped with the ISO. |
| [qubesos.github.io](https://github.com/QubesOS/qubesos.github.io) | www.qubes-os.org itself ([qubes-posts](https://github.com/QubesOS/qubes-posts) supplies blog content). |
| [qubes-secpack](https://github.com/QubesOS/qubes-secpack) | PGP-signed security bulletins, canaries, and the release-key material. |
| [qubes-issues](https://github.com/QubesOS/qubes-issues) | Single issue tracker for the entire project. |
| [qubes-infrastructure](https://github.com/QubesOS/qubes-infrastructure) | Config of the project's own servers. |
| [qubes-architecture](https://github.com/QubesOS/qubes-architecture) | ADRs/design docs (decision record style). |
| [qubes-roadmap](https://github.com/QubesOS/qubes-roadmap) | High-level milestones. |

## Tier 8 — Niche, WIP, or operational

- **Windows**: [qubes-core-agent-windows](https://github.com/QubesOS/qubes-core-agent-windows) and friends (gui-agent-windows, windows-utils, pvdrivers, windows-tools-cross). Second-class but same agent model as Linux.
- **Antievilmaid**: [qubes-antievilmaid](https://github.com/QubesOS/qubes-antievilmaid) — evil-maid attack detection on boot partitions.
- **Hardware/firmware**: [qubes-fwupd](https://github.com/QubesOS/qubes-fwupd), qubes-flashrom, qubes-tpm2-tools, qubes-sbsigntools, qubes-hot uprobes — mostly packaging of tools Qubes cares about.
- **Salt application details**: split across `qubes-mgmt-salt-*` above.
- **Operational junk**: `build-logs*`, `update-status*`, `qubes-hcl`, `qubes-attachment`, `g2g-report`, `panic_report`, `training-materials`, `qubes-translated`, `qubes-diagrams`.

## Naming convention cheat sheet

| Prefix | What it means |
|---|---|
| `core-admin*` | dom0, platform-agnostic qubesd & its clients |
| `core-admin-linux` | dom0 Linux-specific code |
| `core-agent-*` | code running *inside* a VM |
| `core-qrexec` / `core-qubesdb` / `core-vchan-*` | the three IPC layers (RPC, config DB, transport) |
| `gui-*` | GUI virtualization (dom0 daemon or VM agent) |
| `desktop-linux-*` | dom0 as a desktop |
| `app-*` | per-app integration that runs in AppVMs |
| `template-*` | template definitions |
| `mgmt-salt-*` | Salt state modules (Admin API consumers) |
| `builder-*` | build/packaging plugins |
| `vmm-xen*` | the hypervisor & its toolstack |

## Local relevance

Our `00-qubes-base.conf` in this repo is a faithful copy of
`qubes-desktop-linux-i3-settings-qubes`. The qrexec bits we lean on
(`qubes.VMShell`, `admin.*`, dom0-shelling helpers) are defined in
`qubes-core-qrexec` (policy format and `qubes-rpc` client) and
`qubes-core-agent-linux` (the `/etc/qubes-rpc/` service scripts they invoke).
