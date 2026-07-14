## 1. Payload files

- [x] 1.1 Copy `../kanata-enthium/enthium.kbd` to `kanata/enthium.kbd` and add `linux-dev-names-include ("AT Translated Set 2 keyboard")` under `defcfg` (keep first layer `qwerty`)
- [x] 1.2 Write `kanata/kanata.service` with `modprobe uinput`, `--no-wait`, config under `/rw/home/user/kanata/enthium.kbd`, `Restart=on-failure`, and `[Install] WantedBy=multi-user.target`
- [x] 1.3 Write `kanata/kanata-exclusions.conf` drop-in pointing `ExecStart` at `/usr/local/bin/launch-input-sender.py`
- [x] 1.4 Write `kanata/launch-input-sender.py` with default `KEYBOARDS = ["0001:0001"]`, selective mute, sleep/block idle (no busy-spin), exec real sender otherwise
- [x] 1.5 Write `kanata/rc.local.snippet` that installs binary/wrapper/drop-in/unit from `/rw/home/user/kanata/` and enables kanata

## 2. Dom0 install helper

- [x] 2.1 Implement `kanata/install-kanata-sys-usb.sh` (POSIX sh): ensure `personal` exists; ensure `sys-usb-dvm` exists by cloning `default-dvm` if missing
- [x] 2.2 In `personal`, download kanata v1.12.0 `linux-binaries-x64.zip` + `sha256sums`, verify digest, extract `kanata` binary
- [x] 2.3 Copy verified binary + repo payload into `sys-usb-dvm:~/kanata/`, chmod +x binary and wrapper
- [x] 2.4 Append `rc.local.snippet` to `/rw/config/rc.local` in sys-usb-dvm once (idempotent guard)
- [x] 2.5 After staging, switch `sys-usb` → `sys-usb-dvm` with explicit `YES` confirm (default); `--skip-template-switch` to stage only

## 3. Docs

- [x] 3.1 Write `kanata/README.md`: control flow, defaults (`0001:0001`, AT Translated name), install from dom0, lockout risk, revert commands
- [x] 3.2 Add a short pointer in the top-level `README.md` layout section to `kanata/` (no i3 changes)

## 4. Sanity checks

- [x] 4.1 Confirm no `kanata` references under `i3/`
- [x] 4.2 Shellcheck-level read of install script paths (user-agnostic; no hardcoded username beyond Qubes `user` in sys-usb home path as required by Qubes `/rw/home/user`)
- [x] 4.3 Record expected post-install verify commands in README (`systemctl status kanata` in sys-usb, test key in an AppVM)
