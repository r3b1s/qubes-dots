# qubes-ansible

[QubesOS/qubes-ansible](https://github.com/QubesOS/qubes-ansible) — the
official Ansible integration, and the only declarative tool that is
*designed* to run from a qube other than dom0. Status in 4.3:
**experimental** (`developer/releases/4_3/release-notes.rst:240-244`).
Checked against the repo, its RPM specs and the r4.3 yum repos on
2026-10-21.

## Provenance

- Started by Kushal Das as `kushaldas/qubes_ansible` (2018); forked into
  the QubesOS org 2025-03 and announced for testing by fepitre (ITL)
  2025-04 ([forum t/33309](https://forum.qubes-os.org/t/ansible-in-qubes-os/33309)).
- Main contributors: Guillaume Chinal (ITL), Kushal Das, Marek
  Marczykowski-Górecki, fepitre. ~116 commits in 2025, ~90 in 2026.
- **Official component:** listed in `qubes-builderv2`'s r4.3 config next to
  the salt components. Packaged in r4.3: dom0 `qubes-ansible` 1.4.3
  (fc41 host repo), `qubes-ansible-vm` for templates (rpm and deb),
  `qubes-ansible-admin` for a ManagementVM.
- Issues go to qubes-issues (labelled "C: Ansible"); #10004 is still open
  with its document/announce checklist unticked.
- **CI** runs on nested real Qubes 4.3 in two jobs: from dom0
  (`r4.3:mgmt-host`) and from a separate management qube
  (`r4.3:mgmtvm`). ~175 pytest cases.
- Not on Ansible Galaxy (the unrelated `bcduggan.qubes` is).
- qubes-doc has **no Ansible page**. `introduction/faq.rst:848` still
  points at Rudd-O's unofficial ansible-qubes; that text is stale.

## What it ships

Collection `qubesos.core`:

- **`qube` module** — `state` (present/absent/running/halted/restarted/
  pause/destroyed), `klass`, `clone_src`, `template` (+
  `shutdown_if_required`), `properties`, `features` (`null` deletes),
  `services`, `tags`, `notes`, `volumes`, `devices` (strict/append).
- `command` (non-idempotent: `createinventory`, `removetags`, …),
  `qube_facts`, `host_devices_facts`, `qubes_dom0_update`.
- **`qubes` connection plugin** — runs commands over raw qrexec
  (`qrexec-client-vm <vm> qubes.VMShell`/`VMRootShell` from a qube,
  `qvm-run --pass-io` in dom0). Root goes via `VMRootShell`, so no sudo
  needed in minimal templates. File transfer pipes `cat` over VMShell.

Collection `qubesos.security`: the `qubes_proxy` strategy and a callback
that aborts if you use the qubes connection without it. The dom0 RPM makes
`qubes_proxy` the default strategy.

Separate repo `qubes-ansible-collections` (`qubesos.setup`, started
2026-05): roles `bind_dirs`, `split_ssh`, `split_gpg`, `qsvc_qube`,
`qsvc_dom0`. Its `qubes-ansible-setup` package was **not yet in r4.3
current** at time of writing.

All modules import `qubesadmin`, so they behave identically in dom0 and in
a qube — bounded by policy in the latter. Exception: `qubes_dom0_update`
shells out to a dom0-only binary.

## How a run works (`qubes_proxy`)

From #10030 ("Isolate dom0 from untrusted ansible data") — Marek showed
facts gathered from a qube could inject a dom0 command. The fix:

1. Plays targeting `localhost`/dom0 run locally — in a ManagementVM that
   means `qube` module calls over the Admin API.
2. Plays targeting any other qube are tarred, copied into a fresh DispVM
   from that target's `management_dispvm`, and run there via
   `qubes.AnsibleVM`. The controller never sees the target's output
   unfiltered.
3. A ManagementVM asks dom0's `ansible.CreateManagementPolicies` service
   to write a temporary `/run/qubes/policy.d/30-qubes-ansible.policy`
   granting the DispVM shell/filecopy to that one target. dom0 refuses
   unless the target carries `created-by-<mgmtvm>`.

Same isolation model as Salt's `disp-mgmt-*`.

## ManagementVM setup (one-time dom0 work)

From the README "Management VM (advanced)" section and `ci/install_mgmtvm.sh`:

- dom0: `qubes-ansible` (provides the policy-management RPC services).
- management qube's template: `qubes-ansible-admin` (pulls
  `qubes-core-admin-client`).
- `default-mgmt-dvm`'s template: `qubes-ansible-vm`.
- Policy, roughly:
  - `include/admin-local-rwx`: `mgmtvm @tag:created-by-mgmtvm allow target=dom0`
  - `include/admin-global-ro`: `@adminvm`, the created-by tag, and itself
  - read access to netvms and templates you reference (otherwise setting
    `netvm` fails)
  - `admin.vm.Create.{AppVM,StandaloneVM,TemplateVM}`, `admin.vm.Remove`
    (scoped), `admin.vm.volume.CloneFrom` per source template
  - `admin.vm.Create.DispVM +default-mgmt-dvm`
  - `ansible.{Create,Remove}ManagementPolicies`, `qubes.AnsibleVM`,
    `qubes.Filecopy` to `@tag:created-by-mgmtvm`
  - device `Available`/`Assign` if you manage devices

**Review that policy before using it.** Things that make an admin qube
silently dom0-equivalent (see the Admin API report in
[../qubes-admin-api/automation.md](../qubes-admin-api/automation.md)):
`policy.*` write access; self-scoped rwx (lets it set
`tag-created-vm-with` on itself and add arbitrary tags → reach any
`@tag:` rule); `VMShell` or volume import into templates; global rwx over
`management_dispvm`, `updatevm`, `default_template`.

### Limitations

- **Scope is `created-by-mgmtvm` qubes only.** Your existing sys-* and
  AppVMs are out of reach until you tag or re-create them; tagging them
  hands the mgmt qube control of them.
- No cross-host vars/facts; only role files travel to the DispVM (loose
  task files don't); recap counts plays, not tasks.
- Vault secrets are decrypted in the controller and sent in clear unless
  `qubes_proxy_pass_vault_secret` is set.
- Normal Ansible modules need Python in the target template.
- No check-mode support declared.

## Coverage vs Salt `qvm.*`

| Area | `qubesos.core.qube` | Salt |
|---|---|---|
| create / clone / remove | yes (#9932: clone of TemplateVM / StandaloneVM fails) | `present` / `clone` / `absent` |
| prefs, netvm, template switch | yes (`shutdown_if_required`) | `qvm.prefs` |
| features / services | yes, idempotent | yes |
| tags | **add-only**; removal via non-idempotent `removetags` | `qvm.tags` |
| firewall | **none** | `qvm.firewall` |
| devices | strict / append | `qvm.devices` |
| template install | `qubes_dom0_update` — **broken** by #11173 (passes `-y` to qvm-template); `qvm-template` itself works from a mgmt qube over the API | `qvm.template_installed` |
| policy files | none; `ansible.builtin.template` in dom0 only | `file.managed` in dom0 |
| check mode | no | `test=True` (imperfect, #9279) |

Every operation in `opt/qubes-qubesdev-setup.sh` / `opt/qubes-tpl-lolterm.sh`
/ `opt/qubes-workbench-setup.sh` / `opt/qubes-netbird-setup.sh`
(create, clone, prefs, features, service, start/shutdown, run) maps onto
the `qube` module plus the connection plugin. Firewall rules would still
need `qvm-firewall` or Salt.

## Open issues worth watching

#10004 (docs/release), #11168 (F44 management VM), #11173
(template install), #9932 (clone), #10447 (Admin API call volume),
#10672 (docs), #10207 (named disposables).
