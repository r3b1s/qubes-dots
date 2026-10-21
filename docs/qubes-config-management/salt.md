# Salt (`qubesctl`) in Qubes 4.3

Salt is Qubes' native configuration manager and the more mature of the two
official options. It is also **dom0-bound**: `qubesctl` cannot be run from
any other qube. Everything below was checked against qubes-doc @ 37ae9d10
and fresh clones of the `qubes-mgmt-salt*` repos (2026-10-21).

## How a run actually works

`sudo qubesctl [--skip-dom0] [--targets=a,b | --templates | --apps | --all] state.apply ...`

1. **dom0 pass** (skipped with `--skip-dom0`): `qubesctl --dom0-only`
   becomes `salt-call --local` as root against dom0's `/etc/salt`
   (`qubes-mgmt-salt/qubesctl:121-130`). The `qvm.*` states run here.
2. **target list** comes from `qubesadmin.Qubes()` (`qubesctl:73`).
   Templates are processed before other qubes; `--max-concurrency`
   defaults to 4. (`--apps` was renamed from `--app` in 2026-04.)
3. **per target** (`qubessalt/__init__.py`):
   - a DispVM `disp-mgmt-<vm>` is created from the target's
     `management_dispvm` (default `default-mgmt-dvm`: no netvm, internal,
     auto-cleanup);
   - dom0 writes `/etc/qubes/policy.d/30-qubesctl-salt.policy` granting
     that DispVM `qubes.Filecopy`/`VMShell`/`VMRootShell` to the target,
     and removes it afterwards;
   - **all of `/srv`** is copied into the DispVM, but pillars are replaced
     by that one target's pillar, rendered in dom0;
   - `qubes.SaltLinuxVM` runs `salt-ssh` in the DispVM, with an ssh
     wrapper that tunnels over qrexec instead of the network;
   - logs: `/var/log/qubes/mgmt-<vm>.log`.

Why the DispVM: dom0 never parses output from a possibly-malicious target
(`salt.rst:220`). The flip side, also from the docs: the management qube
"has full control over the qubes it's used to manage" (`salt.rst:222-226`)
— so whoever controls `management_dispvm` (a global property) controls
every future target.

The `default-mgmt-dvm` template needs `qubes-mgmt-salt-vm-connector`;
exit code 127 from a run means it's missing.

**4.3:** management disposables can be preloaded to cut startup time:
`qvm-features default-mgmt-dvm preload-dispvm-max 2`
(`how-to-use-disposables.rst:198-217`).

## The `qvm.*` states

`qubes-mgmt-salt-dom0-qvm/_states/ext_state_qvm.py`: `exists`, `missing`,
`running`, `halted`, `start`, `shutdown`, `kill`, `pause`, `unpause`,
`present`, `absent`, `clone`, `run`, `prefs`, `devices`, `service`,
`features`, `tags`, `firewall`, `template_installed`, and the `qvm.vm`
wrapper that combines them.

- prefs/features/tags/service/devices/firewall call `qubesadmin`
  directly; create/remove/clone/run/start/shutdown shell out to `qvm-*`;
  template installs use `qvm-template`.
- **`qvm.present` only creates** — it does not reconcile an existing
  qube. Pair it with `qvm.prefs`, or use `qvm.vm` with `present:` +
  `prefs:`.
- 4.3 additions: Salt module for the new Devices API (#9753);
  `devices_denied` in `qvm.prefs`; `memory` as the canonical key.

## Can it run outside dom0? No.

`qubesctl` writes `/etc/qubes/policy.d`, copies dom0's literal `/srv`,
calls dom0's `qfile-dom0-agent`, and runs `salt-call --local`. No doc
shows it anywhere but dom0, and no open issue proposes changing that.
(sys-gui is *built* by Salt and gets Admin API rights so `qvm-*` works
there — but not `qubesctl`.)

## Layout for a personal config

Directory roots (`etc/salt/minion.d/f_defaults.conf`):

| saltenv | states | pillars |
|---|---|---|
| `base` | `/srv/salt` | `/srv/pillar`, `/srv/pillar/base` |
| `user` | `/srv/user_salt` | `/srv/user_pillar` |
| formulas | `/srv/formulas`, `/srv/user_formulas` | |

- Create the user dirs once: `sudo qubesctl state.apply qubes.user-dirs`.
  They survive package updates.
- A state lives at `/srv/user_salt/<name>/init.sls` with a `<name>.top`
  beside it; `sudo qubesctl top.enable <name>` symlinks it into `_tops/`
  (top files merge).
- Apply: `sudo qubesctl --all state.highstate`, or targeted
  `sudo qubesctl --skip-dom0 --targets=<vm> state.sls <name> saltenv=user`.
- Alternative (qusal's approach): keep states in `/srv/salt/<project>` and
  add a `file_roots` drop-in under `/etc/salt/minion.d/`.
- `/srv` is outside dom0's `$HOME`, so **qvm-backup does not include it**
  (#8853, open). Keep the source of truth in git, not in dom0.

Debugging: suspend `qubesctl` mid-run and re-run `salt-ssh` by hand inside
the management DispVM (`salt.rst:627-655`).

## How much Qubes depends on it

- **Install-time setup:** initial-setup runs `qubesctl top.enable` +
  `--all state.highstate` for sys-net, sys-firewall, default-dispvm,
  disposable sys-*, preloading, the personal/work/untrusted/vault qubes,
  whonix, sys-usb (`qubes-anaconda-addon/.../tasks.py:237-300`).
- sys-gui / sys-gui-gpu / sys-gui-vnc / sys-audio / USB qube setup are
  Salt-only procedures in the docs.
- **Updates no longer use Salt** by default since 4.2:
  `qubes-dom0-update` / `qubes-vm-update` replaced it
  (`4_2/release-notes.rst:104`); `qubes-mgmt-salt-dom0-update` is
  essentially frozen.

Activity since 2025-01-01: dom0-virtual-machines 56 commits (v4.3.19),
dom0-qvm 26, qubes-mgmt-salt 8 (Salt 3008 compatibility, 2026-09),
base-config/base-overrides 0. 38 open "C: Salt" issues.

## Known pain points

- **False "changed" results** on type mismatches (feature `1` vs `"1"`,
  `null`) — #10907; blank `pcidevs` — #10388.
- `qvm.prefs` makes changes even with `test=True` — #9279.
- `saltenv=user` edge cases (#9916, #10108), `top.disable` traces
  (#9915), `--all` with nothing targeting dom0 (#9885).
- Template upgrades break the mgmt DispVM's salt (#10171 F42, #9129
  Debian); an upstream-salt workaround (saltstack#60003) is still sed-patched
  in at runtime.
- One DispVM per target is slow; preloading helps.
- Community unease about upstream Salt's future under Broadcom — no Qubes
  statement; Qubes devs say the plan is to support Ansible *alongside*
  Salt, not replace it.

## Unverified

- Salt version in a current 4.3.2 dom0 (`rpm -q salt` would settle it;
  weekly reviews mention 3007.1, and 2026-09 code adapts to 3008).
