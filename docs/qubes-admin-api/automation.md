# Automating a Qubes host with the Admin API

How to put [the API](README.md) to work: the official client library, the
three places automation can run, and the mechanisms the API exposes
specifically for delegation. Everything here works identically for one host
or many (one policy file per host is the only per-host difference).

## The official client: `qubesadmin`

`qubes-core-admin-client` ships the Python client the `qvm-*` tools
themselves are built on (`import qubesadmin`, Python ≥ 3.10, LGPL). It
picks its transport at import time:

```python
import qubesadmin

app = qubesadmin.Qubes()   # QubesLocal in dom0 (UNIX socket to qubesd),
                           # QubesRemote anywhere else (qrexec call)
```

That single line encodes the whole model: **the same script has full
privileges when run in dom0, and exactly the privileges policy grants to
its qube when run anywhere else.** No rewrite, just policy.

Everyday operations (signatures verified against `qubes-core-admin-client`
master):

```python
import qubesadmin

app = qubesadmin.Qubes()

# list / inspect — admin.vm.List, admin.vm.CurrentState
for vm in app.domains:
    print(vm.name, vm.get_power_state())

# create — admin.vm.Create.AppVM
vm = app.add_new_vm('AppVM', 'my-new-vm', 'red', 'my-template',
                    pools={'private': 'external'})

# properties — admin.vm.property.Set / Get
vm.netvm = app.domains['sys-whonix']
vm.features['service.some-flag'] = '1'

# power — admin.vm.Start / Shutdown
vm.start()

# arbitrary qrexec service from the same client — for custom services
proc = app.run_service('target-qube', 'my.custom.Service')

# exceptions worth catching
from qubesadmin.exc import PermissionDenied, QubesVMError
```

`PermissionDenied` is the policy engine speaking — treat it as a policy
bug, not a code bug. The exception family (`QubesVMNotFoundError`,
`QubesVMAlreadyStartedError`, `QubesMemoryError`, …) maps 1:1 onto
`admin-api` EXCEPTION messages.

### Monitoring: the events stream

`admin.Events` / `admin.vm.Stats` are long-lived connections; the client
wraps them in an asyncio dispatcher with automatic reconnect:

```python
import asyncio
import qubesadmin
from qubesadmin.events import EventsDispatcher

def on_domain_add(subject, event, **kwargs):
    print('new qube:', kwargs)

async def main():
    app = qubesadmin.Qubes()
    dispatcher = EventsDispatcher(app)          # api_method='admin.Events'
    dispatcher.add_handler('domain-add', on_domain_add)
    await dispatcher.listen_for_events(vm=None)  # None = system-wide

asyncio.run(main())
```

Handlers registered per event name; `listen_for_events` never returns
until cancelled and reconnects to `qubesd` with a backoff if the
connection drops. The dispatcher also enables the client's state cache —
run it, or disable caching explicitly.

## Where automation can run

| Place | Privileges | Use for |
|---|---|---|
| **dom0** | total (local socket; policy not consulted for local calls) | bootstrap, trust anchor, things that must never fail |
| **a dedicated ops AppVM** | exactly what `30-*.policy` grants it | day-to-day automation, remote management entry point — see [remote-access-example.md](remote-access-example.md) |
| **a management disposable** | **no `admin.*` access at all** — only a temporary shell/filecopy grant to the one qube it is configuring | configuring the *inside* of a qube without dom0 parsing that qube's output |

The management-disposable mechanism exists because of QSB #45: the
`management_dispvm` property (per-qube, or global via `qubes-prefs`)
names the disposable template from which throwaway VMs run management
code (`default-mgmt-dvm`: hidden from menus, no network, black label).
It is **not** an Admin API client. For each target, the tool creates a
disposable and grants it, for the duration of the run only:

- Salt: dom0 writes `/etc/qubes/policy.d/30-qubesctl-salt.policy` with
  `qubes.Filecopy` / `qubes.VMShell` / `qubes.VMRootShell` from
  `disp-mgmt-<vm>` to `<vm>`, then deletes it
  (`qubes-mgmt-salt` `qubessalt/__init__.py`).
- qubes-ansible: dom0's `ansible.CreateManagementPolicies` writes the
  equivalent into `/run/qubes/policy.d/30-qubes-ansible.policy`, plus
  `admin.vm.CurrentState`/`List` on that one target.

The upstream docs put it bluntly: `default-mgmt-dvm` "has full control
over the qubes it's used to manage" (`user/advanced-topics/salt.rst:226`).
Whoever can change the global `management_dispvm` property therefore
controls every future managed qube. The useful pattern for your own
automation is the same: **code that touches a qube's insides runs in a
disposable, holds no secrets of its own, and disappears when done**.
4.3 can preload them: `qvm-features default-mgmt-dvm preload-dispvm-max 2`.

### Salt — bulk orchestration

`qubesctl` (dom0 only) applies Salt states to many qubes at once and is
the in-box answer to "configure 40 AppVMs consistently". It is two
programs in one:

- **dom0 half** — `salt-call --local` as root in dom0. The `qvm.*` states
  use `qubesadmin`, which in dom0 is `QubesLocal`: it writes straight to
  `qubesd.sock`, so **no qrexec policy is evaluated**. This half also
  edits dom0 files and packages directly, which no API call can do.
- **per-qube half** — `salt-ssh` from a management disposable (above),
  over qrexec.

So Salt is not an Admin API client in the policy-bounded sense; it is a
dom0 program that uses the same client library locally. For state
management and bulk config, prefer `qubesctl`; for process-like
automation (react, poll, start/stop), prefer `qubesadmin`. Since 4.2 the
*update* flow is no longer Salt-based — `qubes-dom0-update` /
`qubes-vm-update` are the recommended CLI updates (Salt still works).
Comparison with qubes-ansible, which *can* run as a policy-bounded
client from a qube:
[../qubes-config-management/](../qubes-config-management/README.md).

## Tags designed for delegation

Tags are how least-privilege policies get written. Verified against
`qubes-core-admin` release4.3:

- `created-by-<QUBE>` — added by the `admin.vm.Create.*` handler itself
  (`qubes/api/admin.py`, marked "TODO: move this to extension"; the
  upstream doc says an extension does it). Only dom0 may set or remove a
  `created-by-*` tag (`qubes/ext/admin.py`).
- `disp-created-by-<QUBE>` — additionally added to disposables made with
  `admin.vm.CreateDisposable`.
- `managed-by-<QUBE>` — **a naming convention only**; nothing in
  `qubesd` knows about it. You set it (`admin.vm.tag.Set`) to mark which
  qubes a manager may touch — and so can *anything else* holding
  `tag.Set` on that qube. Never grant a manager `tag.Set` on qubes it
  doesn't already own, or it can hand itself new ones.

Two features on the *creating* qube shape what it creates:

- `tag-created-vm-with` — space-separated tags added to every qube it
  creates.
- `set-created-guivm` — sets the new qube's `guivm`.

Both are ordinary features, so a manager with `admin.vm.feature.Set` *on
itself* can set them — and through `tag-created-vm-with` reach every
`@tag:` rule in the policy. Don't grant a manager write access to
itself.

This is the idiom for scoping a manager:

```
admin.vm.Start    * ops-mgmt @tag:managed-by-ops-mgmt allow target=dom0
admin.vm.Shutdown * ops-mgmt @tag:managed-by-ops-mgmt allow target=dom0
```

…so `ops-mgmt` can start/stop only the qubes it was explicitly handed —
and only via dom0 (`target=dom0`, always). Build automation so it grants
itself nothing: the `ops` qube asks a dom0-side bootstrap (or a human) to
tag the qubes it should manage.

## Backups without leaking secrets

`admin.backup.Execute` takes only a *config id*; contents and credentials
live in `/etc/qubes/backup/<id>.conf` (YAML, dom0-side):

```yaml
include:
  - $type:AppVM
  - $tag:important
exclude:
  - $tag:do-not-backup
compression: pigz
destination_vm: backup-store
destination_path: /backups
passphrase_vm: vault        # asked via qubes.BackupPassphrase+<id> service
```

An automator can trigger (`Execute`), preview (`Info`), cancel
(`Cancel`) — but never reads the passphrase. If you want automation to
rotate passphrases, the documented hook is making `vault` answer the
`qubes.BackupPassphrase+<id>` service (e.g. generate, encrypt to a public
key, exfiltrate by your own means).

## Practice checklist

1. **Write the policy before the script.** Every `admin.*` line:
   `<call> * <src-qube> <dest-selector> allow target=dom0`. Implicit deny
   covers everything you didn't list.
2. Start with read-only calls (`admin.vm.List`, `admin.vm.CurrentState`,
   `admin.property.Get`); add write verbs one at a time. Global calls
   and the full-list form of `admin.vm.List`/`admin.Events` have dom0 as
   destination, which `@anyvm` does not match — give them a `dom0` line
   ([README.md](README.md#the-targetdom0-rule)).
3. Scope write verbs with `@tag:managed-by-<mgr>`; never `@anyvm` as
   destination for `Set`/`Start`/`Remove`.
4. For dangerous verbs (`admin.vm.Remove`, `policy.Replace`), consider
   `ask` instead of `allow` — the confirmation dialog appears in dom0, so
   a human at the host gates remote actions.
5. Keep the `ops` qube minimal (no browsers, no user files): it is now
   part of your TCB, bounded by its policy lines. Things that silently
   make it dom0-equivalent: `policy.*` write; global
   `admin.property.Set` (`management_dispvm`, `updatevm`,
   `default_template`); `qubes.VMShell` or `admin.vm.volume.Import` into
   templates; `admin.vm.Console`; write access to itself (see tags above).
6. `policy.*` edits: use the `Get`→`Replace` token flow; keep policies in
   git *outside* the host as your rollback.
7. Remember the protocol is not interactive and closing a connection does
   not cancel the operation — scripts must read responses, not fire and
   forget.
