# qubes-dots

i3wm + dmenu + dunst + i3lock port of the hyprland keybinding setup from
[omarchy-overrides](../omarchy-overrides), targeting **dom0** on Qubes OS.
These are portable dots for contiguous *functionality*, not a port of the
rice.

Dom0 is meant to stay free of untrusted application code, so the active
config launches no desktop applications locally: every app keybind runs its
application inside a named AppVM through `qvm-run`, and anything needing a
package beyond the dom0 baseline is kept out of the loaded config entirely.

## Initial install

Paste this into a dom0 terminal to install git, clone this repo (and any
others you list) into `/home/user/Dots` on your `personal` AppVM, then pull
the whole `Dots` directory back into dom0 — see `dom0-clone-dots.sh` for
the equivalent script form:

```bash
VM=personal; DOTS=/home/user/Dots; CLONE_TARS="https://<your-repo-url>"; qvm-run --pass-io "$VM" "sudo dnf install -y git" && qvm-run --pass-io "$VM" "mkdir -p $DOTS" && IFS=',' read -ra U <<< "$CLONE_TARS" && for u in "${U[@]}"; do qvm-run --pass-io "$VM" "git -C $DOTS clone '$u'"; done && qvm-run --pass-io "$VM" "tar -cf - -C $(dirname "$DOTS") $(basename "$DOTS")" | tar -xf - -C "$HOME"
```

Edit `CLONE_TARS` to your own repo URL(s) first. Then run `./install.sh`
from the cloned copy in dom0.

## Layout

```
i3/config          entry point: variables, general settings, autostart
i3/conf.d/         modules loaded via i3's `include` — always active
  10-core.conf     focus / move / resize / layouts / fullscreen / floating
  20-workspaces.conf  numbered + named workspaces, window routing
  30-apps.conf     dmenu launchers, terminals, dunst binds
  40-modes.conf    gaps / passthru modes
  60-bar.conf      i3bar + toggle
  70-qube-apps.conf   AppVM name variables + every app-launching bind
i3/risky-utilities/   reference only, never auto-included
  risky_media.conf     volume, brightness, playback, nightlight, capture
  risky_clipboard.conf color picker, clipboard wipe
bin/               helper scripts (x11-* prefix), symlinked to ~/.local/bin
dunst/dunstrc      notifications
install.sh         symlinks everything into place (user-agnostic, re-runnable)
```

## Install

```sh
./install.sh
```

Required: `i3` and `i3-settings-qubes`, and nothing else. Between them (plus
dom0's own default packages) they supply `dmenu`, `dunst`, `i3lock`,
`xss-lock`, `i3status`, `jq`, and `qvm-run`. The active config — `i3/config`
and everything its `include conf.d/*.conf` picks up — is held to that
baseline deliberately: no bind may need a package you'd otherwise have no
reason to install in dom0.

### Pointing the app binds at your AppVMs

Every application keybind lives in `i3/conf.d/70-qube-apps.conf` and runs
through `qvm-run -a "$vm_…" -- <command>`. The file opens with a block of VM
names:

```
set $vm_browser personal-browsing
set $vm_chat personal-chat
set $vm_vault personal-vault
set $vm_notes personal-notes
set $vm_media personal-media
set $browser_bin brave-origin-beta
```

**These are placeholders.** Edit them to match your real AppVMs (and the
browser binary as it's named inside `$vm_browser`) before the app binds do
anything but produce `qvm-run` errors. No other file needs to change.

Windows opened this way still report their application's own `WM_CLASS`
through Qubes' GUI virtualization, so the `assign` rules in the same file
route them to the right workspace exactly as a local process would.

### Opting into a risky utility

Volume/brightness OSD, screenshots, screen recording, nightlight, the color
picker, and clipboard wipe each need packages beyond the baseline, so they
ship inert under `i3/risky-utilities/` as `risky_<name>.conf`. That
directory sits outside `conf.d/`, so `include conf.d/*.conf` can never pick
it up by accident.

To enable one: install its packages (each file's header lists them), then
either add an explicit `include risky-utilities/risky_media.conf` line to
`i3/config`, or copy the section you want into a file under `conf.d/`.

## Key migration decisions

- **Special workspaces → named i3 workspaces.** Every hyprland scratchpad
  keeps its bind but toggles a named workspace instead. `bin/x11-ws-app`
  reproduces the toggle (press again to bounce back) and launch-on-empty
  behavior. Move-to binds (`$mod+Shift+Ctrl+…`) are plain `move container`.
- **Master layout → i3 layouts.** `$mod+s` toggles tabbed, `$mod+Shift+s`
  stacking, `$mod+Ctrl+s` split orientation, `$mod+Alt+BackSpace` cycles all
  layouts. `$mod+n` / `$mod+Shift+n` walk the container tree (focus
  parent/child) instead of rolling the master stack.
- **hyprland swap vs move** collapse into i3 `move`; the old
  "move without swapping" chord (`$mod+Shift+Ctrl+hjkl`) now moves windows
  across outputs.
- **The fullscreen matrix** (maximize / fake / in-client / typical) collapses
  to i3's `fullscreen toggle` on both `$mod+f` and `$mod+Alt+f`.
- **Submaps → i3 modes**, indicated in i3bar instead of notify-send.
- **delta-resize script → native i3** `resize … 6 ppt`.
- **walker/omarchy-menu → vanilla dmenu**: `$mod+Return` = i3-dmenu-desktop,
  `$mod+space` = dmenu_run, `$mod+Escape` = power menu, keybind cheatsheet on
  `$mod+Shift+Ctrl+Alt+k`.
- **mako → dunst** on the same `$mod+x` family; volume/brightness OSD is done
  with dunst progress notifications.
- **Lock** is `$mod+Shift+Ctrl+Alt+l` (the old omarchy `$mod+Ctrl+l` slot is
  taken by resize) plus the power menu; `xss-lock` covers suspend.

## Intentionally dropped

Wayland/hyprland-only or explicitly unwanted; listed so their absence is a
decision, not an accident:

- Discord mute passthrough (`$mod+apostrophe`) — not wanted
- soundboard binds (`$mod+[Shift/Alt]+apostrophe`) — machine-local, gitignored upstream
- voxtype dictation binds (`$mod+d` is free) — Wayland stack
- window transparency / rounding toggles, "i3 mode" toggle — needs a
  compositor; the point of i3 mode was to look like i3
- monitor scaling binds (`$mod+[Shift]+equal/minus/slash`) — no fractional
  per-monitor scaling on X11
- neowall wallpaper selector, waybar position binds, background/theme menus
- universal copy/paste/cut (`$mod+c/v`), emoji picker, OCR, share/capture
  menus, reminders, audio-output switcher — omarchy tooling
- Moonlight focus toggle (`Shift+Ctrl+Alt+z`) — hyprland `sendshortcut` hack
- Alt+Tab window cycling — no native i3 equivalent
- `lazydocker` (`$mod+Shift+d`), `easyeffects` + `wiremix` (`$mod+Shift+w`),
  `nmtui` wifi (`$mod+Ctrl+w`), `bluetui` bluetooth (`$mod+Alt+w`) — dom0
  owns no NIC, Bluetooth radio, docker daemon, or audio-effects stack for
  these to manage
- `nautilus` (`$mod+e`), `tmux-sessionizer` (`$mod+Ctrl+t`), `inputbox`
  (`$mod+q`), `gnome-calculator` (`XF86Calculator`) — omarchy-era personal
  workflow with no qubes equivalent
- `bin/x11-webapp` — webapp binds now hand the URL to the browser AppVM's
  own `xdg-open`, which loses the chromeless `--app=` window
- `btop` (`$mod+p`, `$mod+Alt+p`) — kept as a workspace bind, but switched to
  plain `top`, which dom0 already ships; the direct-launch `$mod+Alt+p`
  variant is gone

## Notes

- `assign` rules route app windows to their named workspaces; X11 `WM_CLASS`
  values vary by packaging — verify with `xprop WM_CLASS` and adjust in
  `70-qube-apps.conf`.
- `$mod+Alt+t` opens a terminal in this repo by resolving the `~/.config/i3`
  symlink, so it works wherever the repo is cloned.
