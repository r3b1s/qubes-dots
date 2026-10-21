# kanata on Qubes

Layout is the vendored enthium config; binary is kanata **v1.12.0**.

```sh
./kanata/install-kanata-dom0.sh
```

Fetches the release in **`personal`** (sha256 verify); dom0 never downloads.

Shared defaults:

| | |
| --- | --- |
| Device name (kanata) | `AT Translated Set 2 keyboard` |
| Layout | `enthium.kbd` (default layer: **qwerty**) |
| Staging qube | `personal` |
| Release | v1.12.0 (`linux-binaries-x64.zip` → `kanata_linux_x64`) |
| Runs as | dedicated `kanata` user (groups `input`, `uinput`), **not root** |

---

## Dom0 (internal keyboard)

```
physical keyboard (in dom0)
  → kanata grabs by name, applies enthium.kbd
  → uinput virtual keyboard → X / AppVMs via GUI
```

Installs `/usr/local/bin/kanata`, `/etc/kanata/enthium.kbd`, system unit
`kanata.service` (`kanata-dom0.service` in-repo), plus the root config files
`/etc/sysusers.d/kanata.conf`, `/etc/udev/rules.d/99-kanata-uinput.rules` and
`/etc/modules-load.d/kanata.conf`, then `enable --now`.

### Hardening

- Dedicated system user `kanata` (groups `input`, `uinput`) — the service never runs as root.
- No capabilities (`CapabilityBoundingSet=` / `AmbientCapabilities=` empty).
- Read-only filesystem view (`ProtectSystem=strict`, `ProtectHome=yes`) with a private `/tmp`.
- Closed device policy (`DevicePolicy=closed` + `DeviceAllow` lines): the only accessible
  device nodes are the keyboard event nodes (`char-input`) and `/dev/uinput` — nothing else
  on the system is reachable or writable.
- `ExecStartPre` runs `kanata --check`: a rejected config fails before kanata grabs a keyboard.

No input-sender glue — nothing else is claiming the device in dom0.

### Verify / revert (dom0)

```sh
systemctl status kanata --no-pager
journalctl -u kanata -b --no-pager | tail -50
sudo systemctl disable --now kanata
```

If kanata fails or is stopped, the physical keyboard falls through to dom0 with
vanilla (unremapped) keys. Disable it with `sudo systemctl disable --now kanata`.

---

## Trust notes

- Binary is fetched in `personal`, then copied to the install target.
- Dom0 path puts the remapper in dom0 (needed for internal keyboards).
- i3 config does not reference kanata.
