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
| **a management disposable** | same policy as its calling qube, but stateless | one-off management code you don't want persisting anywhere |

The management-disposable mechanism exists because of QSB #45: the
`management_dispvm` property (per-qube, or global via `qubes-prefs`)
names the disposable template from which throwaway VMs run management
code (Salt management uses `default-mgmt-dvm`, which is hidden from menus
and has networking disabled). Treat it as the pattern for your own
automation: **management logic runs in a disposable, holds no secrets of
its own, disappears when done**.

### Salt — bulk orchestration

`qubesctl` (dom0) applies Salt states to many qubes at once and is the
in-box answer to "configure 40 AppVMs consistently". It underlies
management rather than replacing the API: Salt management itself runs
through management disposables. For state management and bulk config,
prefer `qubesctl`; for process-like automation (react, poll, start/stop),
prefer `qubesadmin`. Since 4.2 the *update* flow is no longer Salt-based —
`qubes-dom0-update` / `qubes-vm-update` are the recommended CLI updates
(Salt still works).

## Tags designed for delegation

Two documented tags exist to make least-privilege policies writable
(created in default installs, unused by default):

- `created-by-<QUBE>` — set automatically by a `qubesd` extension at qube
  creation; the value is enforced (not API-writable) and updated on clone.
- `managed-by-<QUBE>` — not automatic; you set it (`admin.vm.tag.Set`) to
  mark which qubes a given manager may touch.

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
   `admin.property.Get`); add write verbs one at a time.
3. Scope write verbs with `@tag:managed-by-<mgr>`; never `@anyvm` as
   destination for `Set`/`Start`/`Remove`.
4. For dangerous verbs (`admin.vm.Remove`, `policy.Replace`), consider
   `ask` instead of `allow` — the confirmation dialog appears in dom0, so
   a human at the host gates remote actions.
5. Keep the `ops` qube minimal (no browsers, no user files): it is now
   part of your TCB, bounded by its policy lines.
6. `policy.*` edits: use the `Get`→`Replace` token flow; keep policies in
   git *outside* the host as your rollback.
7. Remember the protocol is not interactive and closing a connection does
   not cancel the operation — scripts must read responses, not fire and
   forget.
