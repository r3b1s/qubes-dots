## Why

`x11-dots` is a straight port of an omarchy/hyprland i3 keybinding set, intended for **dom0** on Qubes OS 4.3.1 where only the official `i3` and `i3-settings-qubes` packages are installed. As shipped, it launches full desktop applications directly in dom0 (browsers, Signal, Discord, Obsidian, password managers, docker/audio/network tooling), which works against the Qubes security model — dom0 is meant to stay free of untrusted app code — and some of the ported tools (`nmtui`, `bluetui`) can't even function correctly there since dom0 owns no NIC/Bluetooth hardware in a Qubes install. This change makes the config's qubes-specific, minimal-attack-surface nature explicit and structural rather than a matter of convention.

## What Changes

- **BREAKING**: Every app-launching keybind (browsers, chat, password managers, notes, media apps, browser-profile switching, and their webapp shortcuts) is repointed to launch inside a named AppVM via `qvm-run` instead of running locally in dom0. These move out of the general workspace/app config files into a single new `i3/conf.d/70-qube-apps.conf`, with a variables block at the top (`$vm_browser`, `$vm_chat`, `$vm_vault`, `$vm_notes`, `$vm_media`) the user edits to match their real AppVM names.
- **BREAKING**: System-tool workspace binds with no dom0-native equivalent (`lazydocker`, `easyeffects`+`wiremix`, `nmtui` "wifi", `bluetui` "bluetooth") are removed outright — dom0 doesn't own the hardware/services these manage.
- The `btop` workspace bind is kept but switched to plain `top` (installed by default in dom0), preserving a lightweight system-monitor shortcut without adding a package.
- Hardware/utility features that need packages beyond `i3` + `i3-settings-qubes` (volume/brightness OSD, screenshot, screen recording, nightlight, color picker, clipboard wipe) are pulled out of the active config entirely and relocated to a new `i3/risky-utilities/` directory (`risky_media.conf`, `risky_clipboard.conf`) that is never auto-included — reference/copy-paste only.
- Omarchy personal-workflow ceremony with no qubes equivalent (`nautilus`, `tmux-sessionizer`, a personal `inputbox` cargo tool, `gnome-calculator`) is removed.
- `bin/x11-webapp` (local browser-detection helper) is deleted; webapp binds now use `qvm-run -a "$vm_browser" -- xdg-open "<url>"`, letting the target VM's own `xdg-open` pick its default browser.
- `set $browser` is dropped from `i3/config` since VM targeting now lives entirely in `70-qube-apps.conf`.
- README.md and AGENTS.md are updated to document the new baseline (only `i3` + `i3-settings-qubes` required), the qube-apps VM-variable pattern, and the active-vs-reference (`risky-utilities/risky_*.conf`) convention.

## Capabilities

### New Capabilities
- `dom0-i3-baseline`: The active i3 config (everything under `i3/conf.d/` plus `i3/config`) requires nothing beyond `i3` + `i3-settings-qubes`, and contains only window-management, workspace, and qube-launching behavior — no directly-run desktop applications, no packages the two qubes metapackages don't already pull in.
- `qube-app-launching`: Every keybind that opens a user-facing application (browser, chat, password manager, notes, media, webapp shortcuts, browser-profile switching) launches that application inside a named AppVM via `qvm-run`, never directly in dom0, using a single editable block of VM-name variables.
- `risky-utilities-reference`: Hardware/utility features that need packages beyond `i3` + `i3-settings-qubes` (OSD for volume/brightness, screenshots, screen recording, nightlight, clipboard/color-picker tools) exist only as clearly-labeled, non-auto-included reference config under `i3/risky-utilities/`, following a `risky_<name>.conf` naming convention.

### Modified Capabilities
(none — this is the first OpenSpec change for this repo; no existing specs to modify)

## Impact

- Affected files: `i3/config`, `i3/conf.d/20-workspaces.conf`, `i3/conf.d/30-apps.conf`, `i3/conf.d/40-modes.conf`, `i3/conf.d/50-media.conf` (deleted), new `i3/conf.d/70-qube-apps.conf`, new `i3/risky-utilities/risky_media.conf`, new `i3/risky-utilities/risky_clipboard.conf`, `bin/x11-webapp` (deleted), `README.md`, `AGENTS.md`.
- No changes to `install.sh`, `dunst/dunstrc`, or the remaining `bin/` scripts.
- Users of the current config must fill in real AppVM names in `70-qube-apps.conf` before app-launching binds work; until then those binds are no-ops or errors from `qvm-run` targeting a nonexistent VM.
