## ADDED Requirements

### Requirement: Kanata payload is vendored under kanata/ without loading into i3
The repository SHALL ship a self-contained `kanata/` directory with the enthium layout, Qubes input-sender glue, systemd unit, rc.local snippet, and a dom0 install helper. Nothing under `i3/config` or `i3/conf.d/` SHALL start or depend on kanata.

#### Scenario: Active i3 config ignores kanata
- **WHEN** someone greps `i3/config` and `i3/conf.d/*.conf` for `kanata`
- **THEN** there are no matches

#### Scenario: Payload files are present in-repo
- **WHEN** someone lists `kanata/`
- **THEN** it contains at least `enthium.kbd`, `kanata.service`, `kanata-exclusions.conf`, `launch-input-sender.py`, `rc.local.snippet`, `install-kanata-sys-usb.sh`, and `README.md`

### Requirement: Vendored layout defaults to qwerty and targets the host keyboard by name
`kanata/enthium.kbd` SHALL be a copy of the kanata-enthium layout with Qubes-oriented `defcfg` additions. The first `deflayer` SHALL remain `qwerty`. `defcfg` SHALL include `linux-dev-names-include` listing exactly `AT Translated Set 2 keyboard` (unless the operator edits it).

#### Scenario: Default layer is qwerty
- **WHEN** someone inspects the first `(deflayer ...)` form in `kanata/enthium.kbd`
- **THEN** its name is `qwerty`

#### Scenario: Only the named keyboard is grabbed
- **WHEN** kanata starts with `kanata/enthium.kbd`
- **THEN** it registers only devices whose name is `AT Translated Set 2 keyboard`

### Requirement: Input-sender mute is selective for configured keyboard IDs
`launch-input-sender.py` SHALL replace `qubes-input-sender` for `qubes-input-sender-keyboard@*.service` instances via the shipped drop-in. For event nodes belonging to configured `Vendor:Product` pairs it SHALL NOT exec `qubes-input-sender` and SHALL wait without a busy-spin. For all other event nodes it SHALL exec `/usr/bin/qubes-input-sender` with the original arguments. The default configured pair SHALL be `0001:0001`.

#### Scenario: Matched physical keyboard is not forwarded
- **WHEN** systemd starts `qubes-input-sender-keyboard@eventN` for a node whose device is Vendor `0001` Product `0001`
- **THEN** `qubes-input-sender` is not executed for that node

#### Scenario: Unmatched keyboard still forwards
- **WHEN** systemd starts the unit for a keyboard whose Vendor:Product is not in the configured list
- **THEN** `/usr/bin/qubes-input-sender` is executed with the RPC, device path, and target domain arguments

#### Scenario: Idle mute does not spin the CPU
- **WHEN** the wrapper is holding a matched device
- **THEN** it blocks or sleeps rather than tight-looping on `pass`

### Requirement: Kanata runs as a system service with uinput and non-interactive exit
`kanata.service` SHALL start kanata from `/usr/local/bin/kanata` with `--no-wait` and a config path under `/rw/home/user/kanata/`, ensure the `uinput` module is loaded before start, restart on failure, and include an `[Install]` section wanted by a multi-user boot target.

#### Scenario: Service is enableable
- **WHEN** `systemctl enable kanata` is run with the shipped unit installed
- **THEN** enable succeeds because an `[Install]` `WantedBy` is present

#### Scenario: Failure does not hang on stdin
- **WHEN** kanata exits while supervised by the unit
- **THEN** it does not wait for an enter keypress before exiting (`--no-wait`)

### Requirement: Disposable persistence is applied from /rw on each boot
The rc.local snippet SHALL install the binary, python wrapper, systemd drop-in, and unit from `/rw/home/user/kanata/` into system paths, reload systemd, and enable/start kanata so a disposable sys-usb rootfs still runs kanata after reboot.

#### Scenario: Fresh disposable root still remaps after boot
- **WHEN** sys-usb boots from the prepared disposable template after a clean root
- **THEN** rc.local has copied the payload into place and `kanata.service` is active

### Requirement: Dom0 install stages the binary via personal with sha256 verification
A dom0-run helper SHALL download kanata **v1.12.0** `linux-binaries-x64.zip` and the release `sha256sums` inside the **`personal`** qube, verify the zip digest, extract the kanata binary, and copy the binary plus the repo `kanata/` payload into `sys-usb-dvm` at `~/kanata/`. If `sys-usb-dvm` does not exist, the helper SHALL create it by cloning **`default-dvm`** (the stock sys-usb disposable template) and SHALL NOT modify `default-dvm`. After a successful stage, the helper SHALL switch **`sys-usb`** to use template **`sys-usb-dvm`** (with an explicit operator confirmation), unless `--skip-template-switch` is passed. Dom0 SHALL NOT download the release over the network itself.

#### Scenario: Tampered zip is rejected
- **WHEN** the downloaded zip digest does not match `sha256sums` for that file
- **THEN** the helper aborts without copying a binary into sys-usb-dvm

#### Scenario: Successful stage lands files in sys-usb-dvm
- **WHEN** download and verification succeed
- **THEN** `sys-usb-dvm` has `~/kanata/kanata` (executable), `~/kanata/enthium.kbd`, the unit, drop-in, wrapper, and rc.local snippet applied or ready to apply

#### Scenario: Missing sys-usb-dvm is cloned from default-dvm
- **WHEN** `sys-usb-dvm` does not exist and the helper runs
- **THEN** it is created with `qvm-clone default-dvm sys-usb-dvm` and `default-dvm` remains unmodified

#### Scenario: Install switches sys-usb onto sys-usb-dvm
- **WHEN** staging succeeds and the operator confirms the template switch
- **THEN** `sys-usb`'s template is `sys-usb-dvm` and `default-dvm` is unchanged

#### Scenario: Network fetch is not performed in dom0
- **WHEN** the helper runs
- **THEN** the HTTP(S) fetch of the release assets executes inside `personal`, not as a dom0 process

### Requirement: Operator documentation covers lockout and revert
`kanata/README.md` SHALL document the control flow, keyboard identity defaults, install steps, the risk of switching the sys-usb template, and exact revert commands to restore the previous template.

#### Scenario: Revert is documented
- **WHEN** an operator reads `kanata/README.md` after a failed template switch
- **THEN** they can find a dom0 command sequence that shuts down sys-usb, resets its template, and starts it again
