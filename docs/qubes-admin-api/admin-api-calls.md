# Admin API call families

Digest of the canonical call table (`developer/services/admin-api.rst` in
the qubes-doc clone), cross-checked against what Qubes 4.3 actually
implements (`qubes-core-admin` v4.3.53: handlers in `qubes/api/admin.py`,
installed qrexec services in `Makefile`). Where the two disagree, this
file follows the code and says so. Format per call: **dest** is where
qubesd routes the call's effect; **argument** rides after the service
name; **inside** is the payload sent before EOF.

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
| `admin.vm.List` | dom0\|vm | one qube per line: `<name> class=<class> state=<state> uuid=<uuid>`. With dest dom0, `qubesd` filters the list per qube through policy (needs a `dom0` rule *and* per-qube rules — see [README.md](README.md#the-targetdom0-rule)) |
| `admin.vm.Create.<class>` | dom0 | argument: template; payload: `name=<name> label=<label>`. Tags the new qube `created-by-<caller>` |
| `admin.vm.CreateInPool.<class>` | dom0 | same + `pool=` (all volumes) or `pool:<volume>=` (individual) — never both |
| `admin.vm.CreateDisposable` | template | creates a randomly-named disposable from any AppVM with `dispvm_allowed=True`, or from dom0 defaults; **auto-removed on shutdown**. Tags it `created-by-` and `disp-created-by-<caller>`. 4.3: argument `preload` refills the template's preloaded-disposable pool; payload `uuid` returns the new qube's UUID instead of its name |
| `admin.vm.Remove` | vm | |
| `admin.vm.Start` / `Shutdown` / `Pause` / `Unpause` / `Kill` | vm | the power verbs behind `qvm-start` etc. |
| `admin.vm.Suspend` / `Resume` | vm | 4.3; implemented in `qubesd`, but **no `/etc/qubes-rpc` service is installed** for them, so they're reachable only from dom0's local socket |
| `admin.vm.CurrentState` | vm | `power_state`, `mem`, `mem_static_max`, `cputime` |
| `admin.vm.Console` | vm | attach to the qube's console; the stock policy file warns this is equivalent to a shell in it |

`admin.vm.CreateDisposable` vs `admin.vm.Create.DispVM`: the former
generates the name and self-destructs; that's the primitive behind
`$dispvm` targets in qrexec policy.

## properties — the `qvm-prefs`/`qubes-prefs` surface

| Call | Dest | Notes |
|---|---|---|
| `admin.property.List` / `Get` / `GetAll` / `GetDefault` / `Help` / `Reset` / `Set` | dom0 | **global** properties |
| `admin.vm.property.List` / `Get` / `GetAll` / `GetDefault` / `Help` / `Reset` / `Set` | vm | **per-qube** properties |

`*.HelpRst` is documented and has an installed service file, but no
handler in 4.3 — calling it fails.

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

Tags used for delegation (details in
[automation.md](automation.md#tags-designed-for-delegation)):

- `created-by-<QUBE>` — added by the `admin.vm.Create.*` /
  `CreateDisposable` handlers; only dom0 may set or remove it.
- `disp-created-by-<QUBE>` — additionally on API-created disposables.
- `managed-by-<QUBE>` — pure convention, settable by anyone with
  `admin.vm.tag.Set` on that qube.

Features `qubesd` refuses to let the API set (`PROHIBITED_FEATURES` in
`qubes/ext/admin.py`): `deferred-netvm-original` and the internal
`preload-dispvm*` bookkeeping. Everything else, including
`tag-created-vm-with`, is settable by whoever holds `feature.Set`.

## firewall

| Call | Dest | Notes |
|---|---|---|
| `admin.vm.firewall.Get` | vm | one rule per line; syntax as the 4.x firewall interface + `expire=`, `comment=` (must be last) |
| `admin.vm.firewall.Set` | vm | payload: full rule list |
| `admin.vm.firewall.Reload` | vm | force reload without changing rules |

`admin.vm.firewall.Flush` / `GetPolicy` / `SetPolicy` have installed
service files but no handler in 4.3 (the default-action policy became a
rule in 4.0).

This is what `qvm-firewall` fronts. Note the calls are per-vm: outbound
firewall of the *destination* qube.

## devices

| Call | Dest | Notes |
|---|---|---|
| `admin.deviceclass.List` | dom0 | `block`, `usb`, `pci`, `mic` |
| `admin.vm.device.<class>.Available/Assigned/Attached` | vm | listing; optional device-ident argument for a single device |
| `admin.vm.device.<class>.Attach/Detach` | vm | device form `<backend-name>+<device-ident>`; attaches for the current session only |
| `admin.vm.device.<class>.Assign/Unassign` | vm | persistent assignment (what attaches on start), replacing 4.2's `Attach persistent=True` |
| `admin.vm.device.<class>.Set.assignment` | vm | change an existing assignment's mode (e.g. `required`, `auto-attach`, `ask-to-attach`). The qubes-doc table still calls this `Set.required`; the code installs `Set.assignment` |
| `admin.vm.device.denied.List/Add/Remove` | vm | 4.3: device *interfaces* this qube must never be given (`devices_denied`, #9674) |

4.3 dropped 4.2's `admin.vm.device.<class>.List` and
`Set.persistent` in favour of the verbs above (new devices API).

Policy matches the call's argument as `+<backend>+<ident>`; without an
argument in the rule, a grant covers devices from *any* backend qube,
including dom0-backed block and PCI devices.

Device/assignment serialization is ASCII space-separated `key='value'`
pairs (`yes`/`no` booleans, `'unknown'` for None; `_`-prefixed keys are
extra properties). Full format in the admin-api doc.

## storage — pools & volumes

| Call | Dest | Notes |
|---|---|---|
| `admin.pool.List` / `ListDrivers` / `Info` / `UsageDetails` / `Add` / `Remove` | dom0 | pool management |
| `admin.pool.Set.revisions_to_keep` / `Set.ephemeral_volatile` | dom0 | pool defaults |
| `admin.pool.volume.List` | dom0 | the only `admin.pool.volume.*` call implemented — the doc's Info/Snapshot/Revert/Resize/Import/CloneFrom/CloneTo variants don't exist in 4.3; use the `admin.vm.volume.*` forms |
| `admin.vm.volume.List/Info/ListSnapshots/Revert/Resize/Import/Clear` | vm | per-qube volumes (`root`, `private`, …). `admin.vm.volume.Snapshot` is documented but not implemented |
| `admin.vm.volume.Set.revisions_to_keep` / `Set.rw` / `Set.ephemeral` | vm | per-volume settings |
| `admin.vm.volume.ImportWithSize` | vm | new-style import, size may differ |
| `admin.vm.volume.CloneFrom` → `CloneTo` | vm | one-time-use token; invalidated by `CloneTo` even on failure |

`Import`/`ImportWithSize`/`CloneTo` into a template's `root` is code
execution in every qube based on it — treat those grants like
`qubes.VMRootShell` to the template. This is also what `qvm-template`
uses from a management qube (`admin.vm.Create.TemplateVM` +
`ImportWithSize +root`), which makes that qube the trust root for the
templates it installs.

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
| `policy.GetFiles` | service name | — | the policy files relevant to a service (undocumented in qubes-doc; read-only) |

- These live in `qubes-core-qrexec` (`qrexec/policy/admin.py`), not
  `qubesd`, and are gated by `90-admin-policy-default.policy` →
  `include/admin-policy-{ro,rwx}`. That file warns write access
  "effectively gives the caller full control over the system".
- `policy.*` targets `/etc/qubes/policy.d/`; `policy.include.*` targets
  `/etc/qubes/policy.d/include/`. Neither can see the runtime directory
  `/run/qubes/policy.d/` (where qubes-ansible writes its temporary rules).
- Concurrency control: `Get` returns a token (hash of the file);
  `Replace`/`Remove` must echo it back or fail. Pass `new` to create a
  file (asserts non-existence), `any` to skip the check.
- Changes are validated before saving — the policy cannot end up
  *syntactically* invalid (no syntax errors, no dangling includes). A
  valid policy can still lock you out.
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
- No call writes an arbitrary dom0 file, installs a dom0 package, or
  creates a backup profile (`qvm-backup --save-profile` is dom0-only).
  These stay dom0-side no matter how much policy an admin qube is given.
