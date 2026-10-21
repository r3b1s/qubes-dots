# Admin API call families

Digest of the canonical call table (`developer/services/admin-api.rst` in
the qubes-doc clone). Format per call: **dest** is where qubesd routes the
call's effect; **argument** rides after the service name; **inside** is
the payload sent before EOF.

Key structural fact: **every `admin.*` policy rule needs `target=dom0`**
(see [README.md](README.md#the-targetdom0-rule)). The `dest` column says
which qube's state is touched, not where the request goes.

## vmclass / label — the object catalogue

| Call | Dest | Returns |
|---|---|---|
| `admin.vmclass.List` | dom0 | `<class>\n` |
| `admin.label.List` / `Get` / `Index` / `Create` / `Remove` | dom0 | labels (`0xRRGGBB`) |

Labels are what drive the window-border colours; `admin.label.Create`
takes a `0xRRGGBB` payload.

## vm — lifecycle

| Call | Dest | Notes |
|---|---|---|
| `admin.vm.List` | dom0\|vm | one qube per line: `<name> class=<class> state=<state>` |
| `admin.vm.Create.<class>` | dom0 | argument: template; payload: `name=<name> label=<label>` |
| `admin.vm.CreateInPool.<class>` | dom0 | same + `pool=` (all volumes) or `pool:<volume>=` (individual) — never both |
| `admin.vm.CreateDisposable` | template | creates a randomly-named disposable from any AppVM with `dispvm_allowed=True`, or from dom0 defaults; **auto-removed on shutdown** |
| `admin.vm.Remove` | vm | |
| `admin.vm.Start` / `Shutdown` / `Pause` / `Unpause` / `Kill` | vm | the power verbs behind `qvm-start` etc. |
| `admin.vm.CurrentState` | vm | `power_state`, `mem`, `mem_static_max`, `cputime` |

`admin.vm.CreateDisposable` vs `admin.vm.Create.DispVM`: the former
generates the name and self-destructs; that's the primitive behind
`$dispvm` targets in qrexec policy.

## properties — the `qvm-prefs`/`qubes-prefs` surface

| Call | Dest | Notes |
|---|---|---|
| `admin.property.List` / `Get` / `GetAll` / `GetDefault` / `Help` / `HelpRst` / `Reset` / `Set` | dom0 | **global** properties |
| `admin.vm.property.List` / `Get` / `GetAll` / `GetDefault` / `Help` / `HelpRst` / `Reset` / `Set` | vm | **per-qube** properties |

Value encoding in `Get`: `default={True|False}\ntype={str|int|bool|vm|label|list} <value>`
(`list` added in R4.1). `GetAll` packs every property on one line,
newlines escaped as literal `\n`. These are the calls `qvm-prefs` and
`qubes-prefs` are made of.

## features & tags — metadata knobs

| Call | Dest | Notes |
|---|---|---|
| `admin.vm.feature.List/Get/Set/Remove` | vm | string key→value pairs extensions read |
| `admin.vm.feature.CheckWithTemplate` / `CheckWithNetvm` / `CheckWithAdminVM` / `CheckWithTemplateAndAdminVM` | vm | resolve a feature up the template/netvm chain |
| `admin.vm.tag.List/Get/Set/Remove` | vm | `tag.Get` returns `0`/`1`; tags feed qrexec policy selectors `@tag:...` |
| `admin.vm.notes.Get/Set` | vm | ≤256 KiB free text per qube |

Two tags exist specifically to support delegation (see
[automation.md](automation.md#tags-designed-for-delegation)):

- `created-by-<QUBE>` — set by a `qubesd` extension at creation; value
  enforced, not API-writable; updated on clone.
- `managed-by-<QUBE>` — not automatic; settable/resettable via API.

## firewall

| Call | Dest | Notes |
|---|---|---|
| `admin.vm.firewall.Get` | vm | one rule per line; syntax as the 4.x firewall interface + `expire=`, `comment=` (must be last) |
| `admin.vm.firewall.Set` | vm | payload: full rule list |
| `admin.vm.firewall.Reload` | vm | force reload without changing rules |

This is what `qvm-firewall` fronts. Note the calls are per-vm: outbound
firewall of the *destination* qube.

## devices

| Call | Dest | Notes |
|---|---|---|
| `admin.deviceclass.List` | dom0 | `block`, `usb`, `pci`, `mic` |
| `admin.vm.device.<class>.Available/Assigned/Attached` | vm | listing; optional device-ident argument for a single device |
| `admin.vm.device.<class>.Attach/Detach` | vm | device form `<backend-name>+<device-ident>`; `persistent=True` option for attach (default temporary) |
| `admin.vm.device.<class>.Assign/Unassign` / `Set.required` | vm | pre-authorisation without attaching |

Device/assignment serialization is ASCII space-separated `key='value'`
pairs (`yes`/`no` booleans, `'unknown'` for None; `_`-prefixed keys are
extra properties). Full format in the admin-api doc.

## storage — pools & volumes

| Call | Dest | Notes |
|---|---|---|
| `admin.pool.List` / `ListDrivers` / `Info` / `Add` / `Remove` | dom0 | pool management |
| `admin.pool.Set.*` / `admin.pool.volume.*` (List, Info, Snapshot, Revert, Resize, Import, CloneFrom/CloneTo) | dom0 | pool-scoped volume ops |
| `admin.vm.volume.List/Info/Snapshot/Revert/Resize/Import/Clear` | vm | per-qube volumes (`root`, `private`, …) |
| `admin.vm.volume.ImportWithSize` | vm | new-style import, size may differ |
| `admin.vm.volume.CloneFrom` → `CloneTo` | vm | one-time-use token; invalidated by `CloneTo` even on failure |

Sizes are in bytes (`admin.vm.volume.Resize`), which is why `qvm-volume
resize ... 20G` exists — the CLI does the unit math.

## backup

| Call | Dest | Notes |
|---|---|---|
| `admin.backup.Execute` | dom0 | argument: config id; config file `/etc/qubes/backup/<id>.conf` (YAML); one running backup per config id |
| `admin.backup.Info` | dom0 | what would be included |
| `admin.backup.Cancel` | dom0 | |

The API does **not** take backup contents as arguments — what gets backed
up, where, and the passphrase live in the profile file, configured in
dom0. Profile settings: `include`/`exclude` (`$tag:...`, `$type:...`
selectors), `destination_vm`, `destination_path`, `compression`
(`False`/`True`/command like `pigz`), `passphrase_text`, or
`passphrase_vm` (asked via the `qubes.BackupPassphrase+<profile>` service;
empty output cancels). This design keeps secrets out of the API call
stream — an automator can trigger a backup but the *policy* of what it
contains stays dom0-side. See [automation.md](automation.md#backups-without-leaking-secrets) for a
profile example.

## events & stats

| Call | Dest | Notes |
|---|---|---|
| `admin.Events` | dom0\|vm | event stream; connection stays open |
| `admin.vm.Stats` | dom0\|vm | `vm-stats` events every `stats_interval` seconds per running qube: `memory_kb`, `cpu_time` (ms, normalized per CPU), `cpu_usage` (%) |

`admin.Events` is the monitoring primitive — a watcher script subscribes
and reacts to property changes, domain state transitions, etc. An
artificial `connection-established` event arrives first on every stream.

## policy — the API that edits the API's own gate

| Call | Argument | Inside | Return |
|---|---|---|---|
| `policy.List` / `policy.include.List` | — | — | file names (`<name>` — no `.policy` extension) |
| `policy.Get` / `policy.include.Get` | name | — | `<token>\n<content>` |
| `policy.Replace` / `policy.include.Replace` | name | `<token>\n<content>` | — |
| `policy.Remove` / `policy.include.Remove` | name | `<token>` | — |

- `policy.*` targets `/etc/qubes/policy.d/`; `policy.include.*` targets
  `/etc/qubes/policy.d/include/`.
- Concurrency control: `Get` returns a token (hash of the file);
  `Replace`/`Remove` must echo it back or fail. Pass `new` to create a
  file (asserts non-existence), `any` to skip the check.
- Changes are validated before saving — the policy cannot end up invalid
  (no syntax errors, no dangling includes).
- These responses do **not** follow the admin API protocol: errors come as
  exit code + message on stdout.

This family is what makes fully-remote policy administration possible —
and why the remote-access example in
[remote-access-example.md](remote-access-example.md) treats the policy
editing surface as the highest-value target to lock down.

## Known gaps (documented TODOs)

- No notifications/constrained event subscriptions yet (`admin.Events` is
  the current, broad primitive).
- No value constraints on `admin.vm.property.Set` ("may change `netvm`,
  but only from this set") — currently only enforceable by writing a
  `qubesd` extension.
- No `*.desktop` execution call for appmenus without `qubes.VMShell`.
