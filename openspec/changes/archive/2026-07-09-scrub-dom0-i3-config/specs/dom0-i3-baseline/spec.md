## ADDED Requirements

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
