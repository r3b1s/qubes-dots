# AGENTS

## Repo purpose

Portable i3wm + dmenu + dunst + i3lock dots for **dom0** on Qubes OS,
migrated from the hyprland setup in `../omarchy-overrides`. The goal is
contiguous *functionality* across machines — not a port of the hyprland
rice. Resist adding visual styling unless asked.

## Conventions

- User-agnostic paths only: `$HOME`, `~`, or resolution through the
  `~/.config/i3` symlink. Never hardcode a username.
- Helper scripts are POSIX sh, prefixed `x11-`, live in `bin/`, and are
  symlinked into `~/.local/bin` by `install.sh`.
- i3 config is modular via `include conf.d/*.conf`; variables are defined
  in `i3/config` before the includes.
- **`conf.d/` is always-on and must stay within the dom0 baseline** of
  `i3` + `i3-settings-qubes`. Nothing under it may launch a desktop
  application locally — app launches go through `qvm-run` into an AppVM,
  and all of them live in `conf.d/70-qube-apps.conf`.
- **`risky-utilities/risky_*.conf` is copy-paste-only reference** for binds
  that need extra packages. It sits outside `conf.d/` so the glob can't
  reach it. Never glob-include that directory, and never add an `include`
  for one of its files to `i3/config` by default — opting in is the user's
  explicit choice. New deferred features go there as
  `risky_<name>.conf` with a header comment listing their packages.
- Binds mirror the hyprland originals wherever i3 has an equivalent. When a
  bind is dropped or remapped, record it in README.md ("Key migration
  decisions" / "Intentionally dropped") so absences stay deliberate.
- OSD/notifications go through dunst (`dunstify -r <id>` for replaceable
  progress notifications).

## Reference

The source-of-truth for original bind intent is
`../omarchy-overrides/hypr/bindings.lua` (+ submap files) layered on
`../omarchy/default/hypr/bindings/`.
