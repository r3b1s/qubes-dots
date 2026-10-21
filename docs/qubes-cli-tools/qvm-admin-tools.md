# `qvm-*` admin tools (dom0)

Frontends to `qubesd`, the core daemon in dom0. They manage the *system
state* of qubes — existence, power, networking, storage, properties. They
assume dom0 unless a policy grants a domU admin-API access (see
[qrexec.md](qrexec.md)).

Mental model, three groups:

1. **Lifecycle** — create/destroy/power (create, clone, remove, start,
   shutdown, kill, pause/unpause)
2. **Inspect** — ls, check, notes, tags, features
3. **Configure** — prefs, service, firewall, device, volume, pool,
   template + the two `qubes-pref*` cousins

## Lifecycle

### `qvm-create` — make a qube

```console
$ qvm-create --class AppVM --template fedora-41 --label blue myapp
$ qvm-create --standalone --label red my-standalone
```

- `--class/-C`: `AppVM` (default), `StandaloneVM`, `TemplateVM`, `DispVM`
- `--template/-t`, `--label/-l` (required, drives the window border colour),
  `--standalone` / `--disp` shortcuts, `--pool/-P`
- New qubes come up halted; `qvm-start` them separately.

### `qvm-clone` — duplicate a qube, disk files and all

```console
$ qvm-clone work work-copy
```

- `-P POOL` puts the copy in another storage pool; `--class/-C` to clone as
  a different class.

### `qvm-remove` — delete qubes (asks first)

```console
$ qvm-remove --force old-vm
```

- `--all` removes many at once (never dom0); `--force/-f` skips the
  confirmation prompt.

### `qvm-start` / `qvm-shutdown` / `qvm-kill` — power control

```console
$ qvm-start --skip-if-running work
$ qvm-shutdown --wait --timeout 60 work
$ qvm-kill -- "$disp"          # only sane target: a stuck disposable
```

- `qvm-shutdown` is graceful (ACPI), `qvm-kill` is the power cord — like
  `qvm-pause` but permanent; killing a normal qube risks data loss. The
  docs suggest `qvm-kill` for a wedged disposable, `qvm-pause --all` +
  `qvm-xkill` for a GUI meltdown.
- `qvm-shutdown --wait --timeout N` blocks, then force-kills after N
  seconds — the scripting-safe form.
- `qvm-pause` / `qvm-unpause` freeze a domain in RAM (`--suspend/-S` uses
  S3 instead). Paused qubes are killed on system shutdown.

## Inspect

### `qvm-ls` — the one listing tool

```console
$ qvm-ls --running --raw-list      # names only, for shell loops
$ qvm-ls --fields NAME,TEMPLATE,STATE,MEM
```

- `--fields/-O` picks columns (NAME, STATE, CLASS, TEMPLATE, NETVM, MEM,
  DISK…), `--tree/-t` shows the template→qube hierarchy, filters:
  `--running/--paused/--halted`, `--class`, `--tags`.
- `--raw-list` is the flag to reach for in scripts; human columns otherwise.
- `--disk/--network/--kernel` are Qubes 3.x compatibility shorthands.

### `qvm-check` — assert state in scripts

```console
$ qvm-check --running sys-net && do-something
```

Exit-code style predicate over `--running`, `--paused`, `--template`,
`--networked`, `--all`, `--exclude`.

### `qvm-tags` / `qvm-features` / `qvm-notes` — metadata

```console
$ qvm-tags work add trusted       # tags drive qrexec policy (@tag:trusted)
$ qvm-tags work list              # exit 0 if tag set, 1 if not — scriptable
$ qvm-features dom0 preload-dispvm-max 2
$ qvm-notes work --append 'rebuilt 2026-09'
```

- Tags: free-form strings, consumed by qrexec policy lines (`@tag:...`).
- Features: string key→value pairs that Qubes extensions read to change
  behaviour (e.g. `preload-dispvm-max`). The manpage warns these are
  normally extension-managed — set the specific feature a doc tells you to,
  don't improvise.
- Notes: free text per qube (≤256 KiB), included in backups, visible in
  `qvm-ls --fields NOTES`.

## Configure

### `qvm-prefs` — per-qube properties (the big dial panel)

```console
$ qvm-prefs work netvm sys-firewall
$ qvm-prefs work netvm ''         # '' = offline
$ qvm-prefs vmname debug on
$ qvm-prefs --help-properties
```

Booleans accept `True/true/on/1`, `False/false/off/0`; VM-typed properties
accept a qube name or `''`. `--default/-D` resets a property. Common
properties: `netvm`, `template`, `memory`, `maxmem`, `vcpus`, `kernel`,
`qrexec_timeout`, `autostart`, `provides_network`, `management_dispvm`.

### `qubes-prefs` — the global cousins

```console
$ qubes-prefs updatevm
$ qubes-prefs --help-properties
```

Same interface, system-wide properties: `default_template`,
`default_netvm`, `default_pool`, `clockvm`, `updatevm`, `stats_interval`.
Distinct binary, distinct scope — don't conflate with `qvm-prefs`.

### `qvm-service` — toggle Qubes services inside a qube

```console
$ qvm-service -l work
$ qvm-service -e work cups
$ qvm-service -d work cups
```

- `-e`/enable, `-d`/disable, `-D`/back to class default. Defaults vary by
  qube type (e.g. `qubes-firewall` on only in service qubes). The full
  catalogue lives in `qubes-service` docs, not the manpage.

### `qvm-firewall` — per-qube outbound firewall

```console
$ qvm-firewall work add accept dsthost=example.com proto=tcp dstports=443
$ qvm-firewall work list
$ qvm-firewall work reset
```

- Rules: `action` (`accept`/`drop`) + matches (`dsthost`, `proto`,
  `dstports`, `specialtarget`, `expire`…). Default policy is **drop**;
  `reset` restores accept-all. `--reload/-r` pushes rules to a running
  qube.

### `qvm-device` — attach/detach block, USB, PCI, mic devices

```console
$ qvm-device usb list                    # or: block | pci | mic
$ qvm-device usb attach work <usbvm>:2-1
$ qvm-device block detach work
```

- Unified tool since 4.0; `qvm-block`, `qvm-usb`, `qvm-pci` are aliases.
- `attach --persistent/-p` survives reboots (else until detach);
  `attach --ro` read-only; `assign` pre-authorises without attaching.
- PCI can only be *exposed* by dom0. Devices are always
  `backendVM:deviceID` pairs.

### `qvm-volume` / `qvm-pool` / `qvm-template` — storage & templates

```console
$ qvm-volume info work:private
$ qvm-volume resize work:private 20G
$ qvm-pool add foo file-reflink -o dir_path=/mnt/foo
$ qvm-template list --upgrades
$ qvm-template install fedora-41
$ qvm-template upgrade --all
```

- `qvm-volume resize` refuses to shrink without `--force`; `revert` rolls a
  volume back to a revision.
- `qvm-pool` legacy single-flag mode (`-a/-l/-r/...`) is **deprecated since
  4.0.18** — use the subcommand form.
- `qvm-template` is the dom0-side package manager for templates (downloads
  through the UpdateVM, verifies signatures); `--name` installs a copy of a
  template under a new name.

## Backup

```console
$ qvm-backup --compress --dest-vm backup-vm /path/to/dest work personal
$ qvm-backup-restore --verify-only /path/to/backup
```

- Backups are **always encrypted** (`--encrypt` is accepted but ignored)
  and compressed by default.
- From a domU only `--profile` mode works; in dom0 use `--dest-vm` to land
  the backup file in an AppVM rather than dom0's filesystem.

## Renamed / compatibility traps

| Old | Now | Note |
|---|---|---|
| `qvm-start-gui` | `qvm-start-daemon` | renamed; now handles GUI *and* audio |
| `qvm-pool -a/-i/-l/-r/-s` | `qvm-pool add/info/list/remove/set` | legacy mode deprecated 4.0.18 |
| `qubes-yum-proxy` | `qubes-updates-proxy` | service renamed |

`qvm-ls --disk/--network/--kernel` and `qubes-prefs --get/--set` exist only
for old-script compatibility.
