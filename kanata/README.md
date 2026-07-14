# kanata on Qubes

Layout is the vendored enthium config; binary is kanata **v1.12.0**.
Two install paths — pick the one that owns your keyboard:

| Keyboard | Install |
| --- | --- |
| Internal / PS/2 (`AT Translated Set 2 keyboard` in **dom0**) | `./kanata/install-kanata-dom0.sh` |
| USB (device in **sys-usb**) | `./kanata/install-kanata-sys-usb.sh` |

Both fetch the release in **`personal`** (sha256 verify); dom0 never downloads.

Shared defaults:

| | |
| --- | --- |
| Device name (kanata) | `AT Translated Set 2 keyboard` |
| Layout | `enthium.kbd` (default layer: **qwerty**) |
| Staging qube | `personal` |
| Release | v1.12.0 (`linux-binaries-x64.zip` → `kanata_linux_x64`) |

---

## Dom0 (internal keyboard)

```
physical keyboard (in dom0)
  → kanata grabs by name, applies enthium.kbd
  → uinput virtual keyboard → X / AppVMs via GUI
```

```sh
./kanata/install-kanata-dom0.sh
```

Installs `/usr/local/bin/kanata`, `/etc/kanata/enthium.kbd`, system unit
`kanata.service` (`kanata-dom0.service` in-repo), then `enable --now`.

No input-sender glue — nothing else is claiming the device in dom0.

### Verify / revert (dom0)

```sh
systemctl status kanata --no-pager
journalctl -u kanata -b --no-pager | tail -50
sudo systemctl disable --now kanata
```

---

## sys-usb (USB keyboard)

Based on:
https://forum.qubes-os.org/t/running-kanata-keyboard-remapping-software/34959

```
physical keyboard (in sys-usb)
  → launch-input-sender.py  mutes matched Vendor:Product
  → kanata grabs by name, applies enthium.kbd
  → uinput virtual keyboard
  → normal qubes-input-sender  →  dom0 / AppVMs
```

| File | Role |
| --- | --- |
| `kanata.service` | unit for sys-usb (`/rw/home/user/kanata/…`) |
| `kanata-exclusions.conf` | drop-in: keyboard sender → python wrapper |
| `launch-input-sender.py` | mute physical IDs (`0001:0001`); forward rest |
| `rc.local.snippet` | re-install into disposable root each boot |
| `install-kanata-sys-usb.sh` | clone `default-dvm` → `sys-usb-dvm`, stage, switch |

```sh
./kanata/install-kanata-sys-usb.sh          # stages + switches sys-usb template (YES)
./kanata/install-kanata-sys-usb.sh --skip-template-switch
```

**Warning:** template switch can lock out input — keep a backup keyboard.

### Revert (sys-usb)

```sh
qvm-shutdown --wait sys-usb
qvm-prefs sys-usb template default-dvm
qvm-start sys-usb
```

### Verify (sys-usb)

```sh
qvm-run --pass-io sys-usb 'systemctl status kanata --no-pager'
qvm-run --pass-io sys-usb 'journalctl -u kanata -b --no-pager | tail -50'
```

---

## Trust notes

- Binary is fetched in `personal`, then copied to the install target.
- Dom0 path puts the remapper in dom0 (needed for internal keyboards).
- sys-usb path keeps the remapper out of dom0 (preferred for USB).
- i3 config does not reference kanata.
