# AGENTS

## Repo purpose

Portable i3wm + dmenu + dunst + i3lock dots, migrated from the hyprland
setup in `../omarchy-overrides`. The goal is contiguous *functionality*
across machines — not a port of the hyprland rice. Resist adding visual
styling unless asked.

## Conventions

- User-agnostic paths only: `$HOME`, `~`, or resolution through the
  `~/.config/i3` symlink. Never hardcode a username.
- Helper scripts are POSIX sh, prefixed `x11-`, live in `bin/`, and are
  symlinked into `~/.local/bin` by `install.sh`.
- i3 config is modular via `include conf.d/*.conf`; variables are defined
  in `i3/config` before the includes.
- Binds mirror the hyprland originals wherever i3 has an equivalent. When a
  bind is dropped or remapped, record it in README.md ("Key migration
  decisions" / "Intentionally dropped") so absences stay deliberate.
- OSD/notifications go through dunst (`dunstify -r <id>` for replaceable
  progress notifications).

## Reference

The source-of-truth for original bind intent is
`../omarchy-overrides/hypr/bindings.lua` (+ submap files) layered on
`../omarchy/default/hypr/bindings/`.
