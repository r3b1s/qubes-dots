# Other Qubes config-management projects

Survey as of 2026-10-21. Star counts and last-commit dates were read off
GitHub that day; "worth it" is a judgment for *this* repo (one user, wants
declarative, minimal dom0 trust).

| Project | Mechanism | Runs from | Status | Worth it here? |
|---|---|---|---|---|
| [QubesOS/qubes-ansible](https://github.com/QubesOS/qubes-ansible) | Ansible module + qrexec connection + `qubes_proxy` | dom0 **or a ManagementVM** | official, v1.4.3, experimental in 4.3 | **Yes** — see [ansible.md](ansible.md) |
| [qubes-mgmt-salt-dom0-virtual-machines](https://github.com/QubesOS/qubes-mgmt-salt-dom0-virtual-machines) | Salt formulas | dom0 | official, v4.3.19 | Read as the canonical formula reference — see [salt.md](salt.md) |
| [ben-grande/qusal](https://github.com/ben-grande/qusal) | ~55 Salt formulas | dom0 | last commit 2025-10; author says not updated for R4.3, not upstreamed | Learn from, don't adopt |
| [unman/shaker](https://github.com/unman/shaker) + [qubes-task](https://github.com/unman/qubes-task) ([3isec](https://qubes.3isec.org/tasks.html)) | Salt formulas packaged as RPMs; `%post` runs `qubesctl` | dom0, third-party yum repo | active (2026-07/08), 4.3 repo defs exist | Good model for "config as a dom0 package"; installing means trusting a third-party dom0 repo |
| [freedomofpress/securedrop-workstation](https://github.com/freedomofpress/securedrop-workstation) | Salt in signed dom0 RPMs, driven by `sdw-admin` (Python, `qubesadmin`) | dom0 | active, v1.9.0, 4.3 default since 2026-06 | Best production reference; their ADRs (002–004, 007) are worth reading. ADR-007 mentions an "eventual transition to Ansible" |
| [Rudd-O/ansible-qubes](https://github.com/Rudd-O/ansible-qubes) | Ansible via `bombshell-client` / `qubes.VMShell` | dom0, or a VM with a shell into dom0 | last commit 2026-03; the qubes-doc FAQ flags it as unendorsed | No — superseded by the official plugin |
| [deeplow/qubes-terraform-poc](https://github.com/deeplow/qubes-terraform-poc) | Terraform/OpenTofu provider delegating to qubes-ansible | dom0 or mgmt qube | proof of concept, 2026-07 | Watch only |
| [deeplow/qubes-mgmt-tool-parity](https://deeplow.github.io/qubes-mgmt-tool-parity/) | Feature-parity spec: Salt vs Ansible vs qvm-tools vs Terraform | — | 2026-09; README says it is LLM-generated and not fully reviewed | Useful checklist, verify before trusting |
| [originalposter/qixos](https://github.com/originalposter/qixos) | Nix flakes + `qixos-rebuild` over the Admin API from an admin qube | `qixos-admin` qube | alpha, v0.2.0 | Learn from its admin-qube policy design |
| [evq/qubes-nixos-template](https://github.com/evq/qubes-nixos-template) | NixOS TemplateVM | template | 2026-05 | Only if you want NixOS templates |
| [CertainLach/nixos-qubes](https://github.com/CertainLach/nixos-qubes) | NixOS *as dom0* | replaces dom0 | experimental | No |
| [kuhbs](https://github.com/kuhbs/kuhbs-for-qubes) | YAML + bash hooks over `qvm-*` | dom0 | v2 "UNDER DEVELOPMENT" | No (yet) |
| Personal repos: [bcduggan.qubes](https://github.com/bcduggan/bcduggan.qubes), the-cyber-doc/qubes-ansible, monscodex/saltqubes, slchris/qubes-salt-config, scjudd/qubes-workstation | Ansible / Salt | mostly dom0 | 0–5★ | Skim for structure |

Not found: any Puppet, Chef or Pulumi integration. `QubesOS/qubes-config-manager`
does not exist. `qubes-remote-support` is a remote-access tool, not
configuration management.

**Built-in, non-declarative:** Global Config (4.3 adds a Device
Assignments page) and `qubes-policy-editor`. Fine for one-off changes;
they don't provide a source of truth.

**Built-in knob worth knowing:** `vm-config.*` features (4.3, #9837) are
exposed inside the qube via QubesDB — a Qubes-native way to parameterise
per-qube config without a shell. `opt/qubes-netbird-setup.sh` already uses
one (`vm-config.netbird-wt0-subnet`).

## Forum consensus (paraphrased)

- [t/39419](https://forum.qubes-os.org/t/why-is-salt-used-in-qubes-os-for-automation-while-being-so-bad/39419)
  (2026-02), "why is Salt so bad": unman defends Salt when written
  defensively; others call Ansible only marginally better; Ben Grande
  (ITL) says the plan is to support both rather than replace Salt.
- [t/26274](https://forum.qubes-os.org/t/would-you-be-interested-in-ansible-or-opentofu-support/26274)
  (2024): users lean toward Ansible.
- [t/42389](https://forum.qubes-os.org/t/does-anyone-use-kuhbs-on-a-regular-basis/42389)
  (2026-07): running in dom0 is called the biggest drawback, followed by a
  long debate on whether an admin qube actually reduces risk, given it is
  still root over everything it manages.
- In-qube dotfiles ([t/10224](https://forum.qubes-os.org/t/how-do-you-guys-manage-ubiquitous-configs/10224),
  [t/17497](https://forum.qubes-os.org/t/how-to-replicate-dotfiles-across-qubes/17497),
  [t/43338](https://forum.qubes-os.org/t/link-on-boot-a-better-way-to-configure-software-with-salt-template-states/43338)):
  no standard. The common pattern is one source-of-truth qube, files baked
  into the template (`/etc/skel`, `/usr/share`), and per-AppVM symlinks or
  `stow`.
