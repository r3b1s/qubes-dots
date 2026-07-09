# x11-dots

i3wm + dmenu + dunst + i3lock port of the hyprland keybinding setup from
[omarchy-overrides](../omarchy-overrides). These are portable dots for
contiguous *functionality*, not a port of the rice.

## Layout

```
i3/config          entry point: variables, general settings, autostart
i3/conf.d/         modules loaded via i3's `include`
  10-core.conf     focus / move / resize / layouts / fullscreen / floating
  20-workspaces.conf  numbered + named workspaces, window routing
  30-apps.conf     dmenu launchers, terminals, apps, dunst binds
  40-modes.conf    gaps / browser-profiles / passthru modes
  50-media.conf    volume, brightness, playback, capture
  60-bar.conf      i3bar + toggle
bin/               helper scripts (x11-* prefix), symlinked to ~/.local/bin
dunst/dunstrc      notifications
install.sh         symlinks everything into place (user-agnostic, re-runnable)
```

## Install

```sh
./install.sh
```

Required: `i3` (>= 4.22 for `include` + gaps), `dmenu`, `dunst` (provides
`dunstify`/`dunstctl`), `i3lock`, `jq`, `i3status`.

Per-feature (only needed by the binds that use them): `xss-lock` (lock on
suspend/idle), `maim` + `xclip` (screenshots), `ffmpeg` + `xdpyinfo`
(recording), `playerctl`, `pactl`, `brightnessctl`, `redshift` (nightlight),
`numlockx`, `xcolor` (color picker), `perl` (for `i3-dmenu-desktop`).

The default browser is a variable (`set $browser`) in `i3/config`.

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

## Notes

- `assign` rules route app windows to their named workspaces; X11 `WM_CLASS`
  values vary by packaging — verify with `xprop WM_CLASS` and adjust in
  `20-workspaces.conf`.
- `$mod+Alt+t` opens a terminal in this repo by resolving the `~/.config/i3`
  symlink, so it works wherever the repo is cloned.
