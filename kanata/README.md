# kanata on Qubes (sys-usb)

Remap the keyboard in **sys-usb** so every domain receives remapped keys.
Layout is the vendored enthium config; binary is kanata **v1.12.0**.

Based on the community guide:
https://forum.qubes-os.org/t/running-kanata-keyboard-remapping-software/34959

## Control flow

```
physical keyboard (in sys-usb)
  → launch-input-sender.py  mutes matched Vendor:Product (no qubes-input-sender)
  → kanata grabs device by name, applies enthium.kbd
  → kanata uinput virtual keyboard
  → normal qubes-input-sender  →  dom0 / AppVMs
```

| File | Role |
| --- | --- |
| `enthium.kbd` | layout (default layer: **qwerty**) |
| `kanata` | binary (not in git; install fetches it) |
| `kanata.service` | system unit: modprobe uinput, `--no-wait` |
| `kanata-exclusions.conf` | drop-in: keyboard sender → python wrapper |
| `launch-input-sender.py` | mute physical IDs; forward everything else |
| `rc.local.snippet` | re-install into disposable root each boot |
| `install-kanata-sys-usb.sh` | run from **dom0** |

## Defaults for this host

| | |
| --- | --- |
| Device name (kanata) | `AT Translated Set 2 keyboard` |
| Vendor:Product (mute list) | `0001:0001` |
| Staging qube (download) | `personal` |
| Baseline (untouched) | `default-dvm` (stock sys-usb disposable template) |
| Target disposable template | `sys-usb-dvm` (clone of `default-dvm`) |
| Kanata release | v1.12.0 (`linux-binaries-x64.zip` → `kanata_linux_x64`) |

Edit `launch-input-sender.py` / `enthium.kbd` if your IDs or name differ.

## Install (from dom0)

After this repo is on dom0 (have a **backup keyboard** ready):

```sh
./kanata/install-kanata-sys-usb.sh
```

What it does:

1. Ensures `sys-usb-dvm` exists by **cloning `default-dvm`** if missing (`default-dvm` is never modified)
2. In **personal**: downloads zip + `sha256sums`, verifies, extracts binary
3. Copies binary + payload into `sys-usb-dvm:~/kanata/`
4. Appends `rc.local.snippet` to `/rw/config/rc.local` once
5. Points **`sys-usb` → template `sys-usb-dvm`** (after you type `YES`)

Stage only (no template change):

```sh
./kanata/install-kanata-sys-usb.sh --skip-template-switch
```

### Revert

```sh
qvm-shutdown --wait sys-usb
qvm-prefs sys-usb template default-dvm   # or whatever it was before
qvm-start sys-usb
```

**Warning:** switching the sys-usb template can lock out keyboard input. Keep a
second keyboard (or console) available before confirming `YES`.

## Verify

```sh
# service up in the USB qube
qvm-run --pass-io sys-usb 'systemctl status kanata --no-pager'

# logs
qvm-run --pass-io sys-usb 'journalctl -u kanata -b --no-pager | tail -50'

# device still visible / mute list matches
qvm-run --pass-io sys-usb 'grep -A5 "AT Translated" /proc/bus/input/devices'
```

Then type in an AppVM terminal. On qwerty (default) space-hold still opens the
workspaces layer; arrow keys there switch layouts (enthium / miryoku / …).

## Trust notes

- Binary is fetched in `personal` and only then copied into `sys-usb-dvm`.
- Dom0 never downloads the release.
- Kanata does **not** run in dom0; i3 config does not reference it.
