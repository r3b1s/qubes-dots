## Purpose

Keep the active dom0 i3 config runnable with only `i3` + `i3-settings-qubes` installed, with no directly-launched desktop applications or orphaned system-tool binds in dom0, and layered on top of the official Qubes i3 defaults rather than replacing them.

## Requirements

### Requirement: The official Qubes i3 defaults are carried in a vendored base layer
Because i3 reads `~/.config/i3/config` instead of `/etc/i3/config` and never both, and `install.sh` symlinks this repo's `i3/` directory over `~/.config/i3`, the defaults shipped by `i3-settings-qubes` reach the session only if this repo carries them. The active config SHALL include a vendored copy of those defaults at `i3/conf.d/00-qubes-base.conf`, sorted first in the `conf.d` glob, retaining at minimum: the per-VM-label `client.*` colour classes, the `bar` block running `qubes-i3status`, the `for_window` float rules for Tor Browser and `zenity`, and the `xss-lock`, `qubes-i3-xdg-autostart`, and `dunst` autostart execs.

#### Scenario: Auditing the vendored base against the installed package
- **WHEN** someone diffs `i3/conf.d/00-qubes-base.conf` against the `## VARS BEGIN` section onward of `/etc/i3/config`
- **THEN** every retained directive matches upstream verbatim, and every upstream directive that is absent is named, with a reason, in the file header's "Deliberately NOT carried over" list

#### Scenario: A Qubes-provided menu or helper is needed by a bind
- **WHEN** a bind needs an application launcher, a terminal, or a status bar
- **THEN** it uses the Qubes-provided tool (`j4-dmenu-desktop` with upstream's arguments, `qubes-app-menu`, `qubes-i3-sensible-terminal`, `qubes-i3status`) rather than a generic i3 equivalent, so that launched applications and terminals resolve into the correct qube

### Requirement: Module load order respects i3's non-uniform override semantics
i3 resolves duplicate `bindsym`/`bindcode` and `bar` declarations as *first* wins, provides no `unbindsym`, accumulates `exec` lines irremovably, and applies scalar settings as *last* wins. Modules under `conf.d/` SHALL therefore never redeclare a keybinding or a `bar` block already declared by `00-qubes-base.conf`; they may override only scalar settings.

#### Scenario: Validating the layered config
- **WHEN** someone runs `i3 -C -c i3/config`
- **THEN** it reports zero `Duplicate keybinding` errors, and a running session exposes exactly one bar whose `status_command` is `qubes-i3status`

### Requirement: Window borders remain a Qubes trust indicator
The window titlebar carries the owning qube's name and the border carries its label colour; together they are how a user identifies which VM owns a window. The active config SHALL leave `default_border` at i3's `normal`, SHALL retain the full set of `client.<label>` colour lines from upstream, and SHALL NOT bind any action that changes border width.

#### Scenario: Reviewing border configuration
- **WHEN** someone greps the active config for `default_border`, `default_floating_border`, or a `border pixel` command
- **THEN** no match sets a pixel border or rebinds border width, and the `client.<label>` colour classes for every Qubes label are present in `00-qubes-base.conf`

### Requirement: No package beyond i3 + i3-settings-qubes for the active config
The set of i3 config files that are automatically loaded when i3 starts (`i3/config` and everything matched by its `include conf.d/*.conf` directive) SHALL NOT require any package to be installed beyond `i3` and `i3-settings-qubes`.

#### Scenario: Fresh dom0 with only i3 + i3-settings-qubes installed
- **WHEN** a user with only `i3` and `i3-settings-qubes` installed in dom0 runs `install.sh` and starts/reloads i3
- **THEN** every keybind reachable from the default config (`i3/config` plus its `conf.d/*.conf` includes) either works immediately or fails only because a target AppVM hasn't been configured yet — never because a local binary is missing

#### Scenario: Auditing the active config for stray dependencies
- **WHEN** someone greps `i3/config` and `i3/conf.d/*.conf` for `exec` lines
- **THEN** every referenced binary is either an i3/i3-settings-qubes-provided tool, a `bin/x11-*` script in this repo, or `qvm-run`/`qvm-*` (a Qubes dom0-native tool)

### Requirement: No directly-launched desktop applications in the active config
The active config SHALL NOT contain a keybind that runs a full desktop application (browser, chat client, password manager, notes app, media app, or similar) as a local dom0 process.

#### Scenario: Reviewing exec targets in the active config
- **WHEN** someone lists every `exec`/`exec --no-startup-id` target across `i3/config` and `i3/conf.d/*.conf`
- **THEN** none of them directly invoke a browser, chat client, password manager, notes app, or media app binary/flatpak in dom0 — any such application launch instead goes through `qvm-run` into a named AppVM

### Requirement: System-tool binds with no dom0-native equivalent are absent
The active config SHALL NOT bind tools that manage hardware or services dom0 does not own in a Qubes install (network interfaces, Bluetooth, containers, audio-effects processing).

#### Scenario: Reviewing workspace and direct-launch binds for orphaned system tools
- **WHEN** someone searches the active config for `nmtui`, `bluetui`, `lazydocker`, or `easyeffects`
- **THEN** no matches are found — dom0 has no NIC/Bluetooth hardware and no docker/audio-effects stack to manage, so these binds would either fail or misleadingly operate on the wrong thing
