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

- **`conf.d/00-qubes-base.conf` is a vendored copy of the official
  `i3-settings-qubes` config** (`/etc/i3/config`) and must stay faithful to
  it. i3 reads `~/.config/i3/config` *instead of* `/etc/i3/config`, so those
  defaults only reach us through that file. Never delete a `client.<label>`
  colour line, the `for_window` rules, or an `exec` from it without saying why
  in its header's "Deliberately NOT carried over" list. Upstream's `bar` block
  is already listed there: it now lives in `conf.d/15-bar.conf`.

- **Glob order in `conf.d/` is load-bearing.** i3 resolves duplicate
  `bindsym` and `bar` declarations as *first* wins and has no `unbindsym`;
  scalar settings (`font`, `gaps`, `client.*`) are *last* wins; `exec` lines
  accumulate and cannot be removed. So `00-` supplies binds/execs, and later
  modules may override scalars but must never redeclare a bind the base
  already declares. Validate with `i3 -C -c "$PWD/i3/config"` — it must report
  no duplicate keybindings, and nothing but `Could not parse color: <label>`,
  which is stock i3 rejecting the Qubes label-colour patch.

- **There is exactly one `bar` block, in `conf.d/15-bar.conf`.** A second one
  anywhere spawns a second bar rather than overriding the first, even with a
  matching `id`, so a `bar` can only be changed where it is declared. That is
  why it sits in our layer instead of the vendored copy.

- **Display layout lives in `i3/monitor.conf`**, applied by `bin/x11-monitor`
  from `conf.d/05-monitors.conf`. It is not i3 syntax and sits outside
  `conf.d/` so the glob cannot reach it. i3 does no mode-setting, so refresh
  rate and monitor arrangement go through xrandr there, never into a conf.d
  module.

- Window borders are a Qubes trust indicator (titlebar = qube name, border
  colour = qube label), not a style knob. Leave `default_border` at i3's
  `normal` and do not add binds that change border width.

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

- OSD/notifications go through dunst (`dunstify -r <id>` for replaceable
  progress notifications).

