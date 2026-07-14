## Why

Complex keyboard layouts (Enthium + home-row mods) need to apply once and reach every domain. X11 remaps in dom0 do not propagate cleanly to AppVMs; kanata at the USB/input qube remaps before Qubes forwards keys. This ports the community sys-usb pattern into qubes-dots with the kanata-enthium layout and kanata v1.12.0.

## What Changes

- Add a `kanata/` tree: vendored `enthium.kbd`, Qubes-adapted systemd unit, input-sender drop-in, `launch-input-sender.py`, and rc.local snippet
- Add a **dom0-run** install helper that stages the kanata v1.12.0 linux x64 binary in the `personal` qube (download + sha256 verify), then copies payload into `sys-usb-dvm`
- Document install, template switch, lockout recovery, and keyboard identity (`AT Translated Set 2 keyboard`, `0001:0001`)
- Default base layer stays **qwerty**; no i3/conf.d changes

## Capabilities

### New Capabilities
- `kanata-sys-usb`: Install and run kanata in a disposable sys-usb template so remapped keys are what Qubes forwards system-wide

### Modified Capabilities
- (none — dom0 i3 baseline and qube-app-launching stay unchanged)

## Impact

- New directory: `kanata/` (empty placeholder already present)
- New dom0 script (under `bin/` or `kanata/`) orchestrating personal → sys-usb-dvm staging
- Runtime: `sys-usb-dvm` / `sys-usb` only — binary, uinput, and input-sender override live there, not in dom0
- External: kanata v1.12.0 release assets; layout source `../kanata-enthium/enthium.kbd` (vendored copy)
- Operator risk: switching `sys-usb` template can lock out input if misconfigured; README must include revert steps and a backup keyboard note
