# Declarative Qubes configuration management

Internal reference for managing this machine's qubes, templates and policy
*declaratively* — and, as far as Qubes allows, without typing into dom0.
Companion to [../qubes-admin-api/](../qubes-admin-api/README.md), which
covers the API every tool here ultimately drives. The imperative
`opt/*.sh` provisioners stay as the fallback path; nothing here replaces
them yet.

Sources of truth (current as of 2026-10-21, Qubes OS **4.3.2**, released
2026-10-02):

- qubes-doc @ 37ae9d10 — `user/advanced-topics/salt.rst`,
  `developer/services/admin-api.rst`,
  `developer/releases/4_3/release-notes.rst`,
  `user/how-to-guides/how-to-use-disposables.rst`
- Source: `qubes-mgmt-salt`, `qubes-mgmt-salt-dom0-qvm`,
  `qubes-mgmt-salt-dom0-virtual-machines`, `qubes-core-admin` (release4.3),
  `qubes-core-admin-client`, `qubes-core-qrexec`, `qubes-ansible`
- [qubes-issues#10004](https://github.com/QubesOS/qubes-issues/issues/10004)
  (Ansible support), [#10030](https://github.com/QubesOS/qubes-issues/issues/10030)
  (isolating dom0 from Ansible data)

## Short answers

**Salt or Ansible — which is more mature?** Salt, by every measure except
momentum. It is documented (a 700-line `salt.rst`), it is what Qubes uses
to build its own default qubes at install time (sys-net, sys-firewall,
whonix, sys-usb, sys-gui, `default-mgmt-dvm`), and openQA exercises it.
qubes-ansible is an official, ITL-maintained, packaged component with
nested-Qubes CI, but 4.3 lists it under *"New/Improved experimental
features"*, qubes-doc has no page for it, and its README still warns the
syntax may change. Details: [salt.md](salt.md), [ansible.md](ansible.md).

**Can I avoid shelling into dom0?** For *qube state* (create, clone,
prefs, features, tags, devices, template installs): yes, via an admin qube
on the Admin API — qubes-ansible's ManagementVM mode is the supported way
to do that declaratively. For *dom0's own files* (this repo's i3/dunst
dots, `/etc/qubes-rpc` services, `/srv/salt`) and dom0 packages: no — the
Admin API has no call that writes a dom0 file. Some dom0-side step is
unavoidable; the goal is to make it narrow, verified and non-interactive.
See [dom0-free-patterns.md](dom0-free-patterns.md).

**"Ansible and Salt just implement the Admin API" — true?** Half true:

| Tool | dom0-side half | per-qube half |
|---|---|---|
| Salt (`qubesctl`) | root `salt-call --local` **in dom0**. `qvm.*` states use `qubesadmin`, which in dom0 is `QubesLocal` — straight to `qubesd.sock`, **no qrexec policy evaluated**. Also writes dom0 files/packages directly. | `salt-ssh` from a per-target management disposable over qrexec. That disposable gets **no** Admin API access, only a temporary shell/filecopy grant to its one target. |
| qubes-ansible | Can run in dom0 *or* in a ManagementVM. Modules import `qubesadmin`, so from a qube they are genuine Admin API clients, bounded by policy. | Same isolation model as Salt: plays proxied into a per-target management disposable (`qubes_proxy` strategy). |

So Ansible-from-a-ManagementVM is the only one that *is* "an Admin API
client"; Salt is a dom0 program that happens to use the same client
library locally.

**What else exists?** Community Salt collections (qusal, unman's shaker),
SecureDrop Workstation as a production reference, and a handful of young
Nix/Terraform experiments. None displaces the two official options. See
[landscape.md](landscape.md).

## Recommendation for this repo

1. **Qube & template topology → qubes-ansible from a management qube**
   (once its policy is reviewed), scoped by `created-by-<mgmtvm>`. This is
   the only declarative path that runs outside dom0.
2. **dom0's own files (i3 dots, policy, rpc services) → a narrow,
   signature-verified apply step that dom0 runs**, triggered by a fixed
   qrexec service rather than a general shell. Salt in dom0 is a fine
   engine for that step if you want it declarative.
3. **Fallbacks stay:** `opt/*.sh`, `dom0-*-dots.sh`, and `dev.Shell` on the
   test machine.

Salt-everything-from-dom0 is the *more mature* choice and remains
perfectly defensible; it just doesn't meet the "no dom0 typing" goal
without the trigger pattern in item 2.

## Files

| File | What's in it |
|---|---|
| [salt.md](salt.md) | How `qubesctl` actually works in 4.3, layout for a personal config, known bugs |
| [ansible.md](ansible.md) | qubes-ansible: provenance, modules, ManagementVM mode + policy, gaps vs Salt |
| [landscape.md](landscape.md) | Other projects, maintenance status, worth-it judgments, forum consensus |
| [dom0-free-patterns.md](dom0-free-patterns.md) | Ways to apply config without a dom0 shell; what dom0 must still do; layered design |
