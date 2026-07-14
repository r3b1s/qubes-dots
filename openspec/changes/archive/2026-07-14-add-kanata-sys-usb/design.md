## Context

Keyboard remapping must apply before Qubes forwards input, or AppVMs only see raw keycodes. Community guide ([forum #34959](https://forum.qubes-os.org/t/running-kanata-keyboard-remapping-software/34959)) runs kanata in a disposable sys-usb template and mutes physical keyboards in `qubes-input-sender` so only kanata’s uinput device is forwarded.

This machine’s target keyboard is visible in sys-usb as:

- Name: `AT Translated Set 2 keyboard`
- IDs: Vendor `0001`, Product `0001` (`0001:0001`)

The same name can appear in dom0 as the **forwarded** stream; ownership for remapping stays sys-usb.

Layout source: `../kanata-enthium/enthium.kbd` (vendored into this repo). Kanata version: **v1.12.0** (not guide’s 1.9.0). Binary is never built or fetched in dom0 — staged via `personal`.

Empty `kanata/` already exists in-repo.

## Goals / Non-Goals

**Goals:**

- Remap at sys-usb so every domain receives remapped keys
- Vendor enthium layout; default layer remains `qwerty`
- Dom0-driven install: download+sha256 in `personal`, copy into `sys-usb-dvm`, wire systemd/rc.local
- Document lockout risk and revert for sys-usb template switch
- Stay out of `i3/conf.d` and the dom0 package baseline

**Non-Goals:**

- Building kanata from source in any qube
- Running kanata in dom0
- Supporting multiple keyboards beyond the one configured ID/name (easy to extend later)
- Switching `sys-usb` template without typing `YES` (lockout safety)
- Shipping the kanata binary in git

## Decisions

### 1. sys-usb-dvm, not dom0

**Choice:** Follow the community guide: kanata + input-sender override live in `sys-usb-dvm` → template of `sys-usb`.

**Why:** Physical device is present in sys-usb; remapping there propagates; keeps untrusted binary out of dom0.

**Alt:** dom0 kanata — simpler for pure i8042-only hosts, worse trust model, rejected.

### 2. Prebuilt v1.12.0 from GitHub, staged in `personal`

**Choice:** Dom0 helper runs in `personal`:

1. `curl`/`fetch` `linux-binaries-x64.zip` + `sha256sums` for tag `v1.12.0`
2. Verify zip hash
3. Extract `kanata` binary
4. `qvm-copy-to-vm` / `qvm-run` into `sys-usb-dvm:~/kanata/`

**Why:** No rustc in USB qube; dom0 never touches the network for the binary; sha256 catches tampered downloads.

**Alt:** Vendor binary in git — bloated and stale. Build in personal — slower, more deps.

### 3. Selective mute via drop-in + python wrapper

**Choice:** Keep guide’s pattern:

- drop-in on `qubes-input-sender-keyboard@.service` → `launch-input-sender.py`
- `KEYBOARDS = ["0001:0001"]` for this host
- matched event nodes: block (sleep loop, not busy-wait)
- unmatched: `exec` real `qubes-input-sender`

**Why:** Prevents double-forward of the physical device; virtual kanata device is not in the list so it still forwards.

**Alt:** Disable all keyboard input-sender units — breaks other keyboards / recovery devices.

### 4. Device filter dual-key: python VID:PID + kanata device name

**Choice:**

- Python list: `0001:0001`
- `enthium.kbd` `defcfg`: `linux-dev-names-include ("AT Translated Set 2 keyboard")`

**Why:** Guide recommends name include to avoid grabbing mice/power keys; VID:PID is what the sender wrapper can match from `/proc/bus/input/devices`.

**Note:** `0001:0001` is generic. Acceptable while this is the only keyboard in sys-usb; document how to tighten.

### 5. Vendored layout copy

**Choice:** Copy `enthium.kbd` into `kanata/enthium.kbd`; add only the linux-dev-names-include (and any path renames for Qubes). Default first layer stays `qwerty`.

**Why:** qubes-dots stays self-contained for dom0 sync; no runtime dependency on sibling repo.

### 6. Service shape (vs guide)

Guide unit is incomplete for production. Ours:

```
ExecStartPre=/usr/sbin/modprobe uinput   # or /sbin — detect in install
ExecStart=/usr/local/bin/kanata --no-wait -c /rw/home/user/kanata/enthium.kbd
Restart=on-failure
[Install] WantedBy=multi-user.target
```

Config path under `/rw/home/user/kanata/` so it survives disposable rootfs.

### 7. Persistence via `/rw/config/rc.local`

Disposable root loses `/usr` and `/etc/systemd` each boot. rc.local copies binary, wrapper, drop-in, unit from `/rw/home/user/kanata/`, then daemon-reload / enable / start.

### 8. Repo layout

```
kanata/
  README.md
  enthium.kbd
  kanata.service
  kanata-exclusions.conf
  launch-input-sender.py
  rc.local.snippet
  install-kanata-sys-usb.sh   # run from dom0
```

Optional: thin symlink from `bin/` only if we want it on PATH via existing `install.sh` — prefer keeping the installer next to its payload and documenting `./kanata/install-kanata-sys-usb.sh` so `install.sh` stays i3/dunst-only.

## Risks / Trade-offs

- **[Lockout on template switch]** → Document backup keyboard; print revert before switch; require typing `YES`; `--skip-template-switch` for stage-only.
- **[Generic 0001:0001 mute]** → README warns; name-based kanata include limits grab side; operator can edit KEYBOARDS.
- **[Device in both domains confuses debugging]** → README: physical in sys-usb, dom0 entry is forwarded; inspect sys-usb for kanata logs.
- **[Busy-wait in guide script burns CPU]** → Use `time.sleep` / signal pause.
- **[uinput module missing]** → `ExecStartPre=modprobe uinput`.
- **[Guide unit missing [Install]]** → Add `WantedBy=multi-user.target`.
- **[v1.12 CLI drift]** → Pin tag + sha256; `--no-wait` confirmed present in 1.12 args.

## Migration Plan

1. Land files in repo; operator runs install from dom0 after dots sync.
2. Install creates `sys-usb-dvm` via `qvm-clone default-dvm` when missing (leaves `default-dvm` clean), stages files, appends rc.local once.
3. Install then switches `sys-usb` → `sys-usb-dvm` after operator types `YES` (`--skip-template-switch` to stage only).
4. Rollback: restore previous sys-usb template (usually `default-dvm`).

## Open Questions

- (none open for baseline clone; install records prior sys-usb template at switch time.)
- Whether `modprobe` path is `/usr/sbin` or `/sbin` in current Fedora template — probe or use `modprobe` on PATH under root.
- Confirm zip member name inside `linux-binaries-x64.zip` for v1.12.0 at implement time (extract listing).
