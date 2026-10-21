# Qubes CLI tools

Internal reference for the command-line entrypoints that are unique to Qubes
OS. Written for humans *and* agents: when a script or conf module reaches for
a `qvm-*` / `qubes-*` tool, check here first for what it does, where it is
allowed to run, and what it needs.

Sources of truth (current as of 2026-10, qubes-doc @ bb9da3f5):

- `/home/t/3rdParty/qubes-doc/` — official docs source, local clone
- `user/reference/tools.rst` in that clone — canonical Dom0/DomU tool split
- Manpages: `qubes-core-admin-client` repo (`doc/manpages/*.rst`); DomU tools
  live in their owning repos (`qubes-core-agent-linux`,
  `qubes-core-qrexec`, `qubes-desktop-linux-common`)

## Where a tool runs

Qubes splits its CLI surface by *domain*, not by package. The deciding
question for any new bind or helper is: **which qube is this process in when
it runs?**

| Domain | Who lives there | Tools available there |
|---|---|---|
| **dom0** (the admin qube) | Nothing but the window manager and core tooling | All `qvm-*` core-admin-client tools, `qubes-prefs`, `qubesctl`, `qubes-dom0-update`, `qubes-vm-update`, `qubes-fwupdmgr`, `qrexec-client`, `qvm-appmenus`, `qvm-xkill` |
| **AppVM / template / disposable** (domU) | User applications and their agents | `qvm-run-vm`, `qvm-copy`, `qvm-move`, `qvm-open-in-vm`, `qvm-open-in-dvm`, `qvm-convert-pdf`/`-img`/`-file`, `qrexec-client-vm` |
| **Any qube with a policy** | — | Anything gated by `/etc/qubes/policy.d/` — e.g. a domU can reach `admin.*` API calls only if a policy line allows it to dom0 |

Rules of thumb:

1. **`qvm-*` management tools run in dom0.** They are frontends to `qubesd`,
   the daemon in dom0. Their manpages rarely say "dom0" because it is
   assumed; `user/reference/tools.rst` is the canonical list of what lives
   where. Running them from a domU is possible *only* through the admin API
   (`admin.*` qrexec calls) with an explicit allow policy — see
   [qrexec.md](qrexec.md).
2. **DomU tools are the inverse.** `qvm-copy`, `qvm-move`,
   `qvm-open-in-vm`, `qvm-open-in-dvm` are documented as *not* working in
   dom0 — they run inside a qube and reach out via qrexec. If a helper
   script in this repo's `bin/` needs to copy a file from an AppVM, that
   script must run *in* the AppVM (e.g. via `qvm-run`), not in dom0.
3. **dom0 desktop integration tools** (`qubes-i3status`,
   `qubes-i3-sensible-terminal`, `qubes-i3-xdg-autostart`,
   `qubes-input-sender`, `qvm-xkill`, `qvm-appmenus`) come from
   `qubes-desktop-linux-*` packages and only make sense in dom0, where the
   GUI domain and the input devices live.

## Contents

- [qvm-admin-tools.md](qvm-admin-tools.md) — the `qvm-*` lifecycle tools
  (create, run, clone, devices, backup…), dom0-resident
- [domu-tools.md](domu-tools.md) — tools that run *inside* a qube
  (copy/move, open-in-vm, converters, `qvm-run-vm`)
- [qrexec.md](qrexec.md) — the RPC layer: `qrexec-client-vm`,
  `qrexec-client`, the admin API, and policy files
- [dom0-desktop-tools.md](dom0-desktop-tools.md) — the Qubes desktop
  integration binaries this repo's i3 config and `bin/` scripts actually
  invoke (`qubes-i3*`, `qubes-input-sender`, `qvm-appmenus`, `qvm-xkill`)

## Glossary (qube types, one line each)

- **dom0** — the host domain; a type of admin qube; runs the Xen management
  toolstack with special privileges.
- **admin qube** — a qube used for administering Qubes OS; in the default
  install the only admin qube is dom0.
- **app qube** — based on a template; runs user applications and stores
  user files (formerly "AppVM").
- **template** — provides its root filesystem to other qubes; for
  installing/updating software, not running it.
- **standalone** — has its own root filesystem, shares it with no one.
- **disposable** — stateless qube, typically named `dispNNNN`; ceases to
  exist after shutdown (formerly "DispVM").
- **service qube** — an app qube whose primary purpose is providing
  services to other qubes (`sys-net`, `sys-firewall`).
