## Purpose

Keep i3 features that require packages beyond `i3` + `i3-settings-qubes` available as opt-in reference config under `i3/risky-utilities/`, never wired into the active config automatically.

## Requirements

### Requirement: Extra-package features exist only as non-active reference config
Any i3 feature whose binds require a package beyond `i3` + `i3-settings-qubes` (brightness OSD, playback control, screenshot, screen recording, nightlight, color picker, clipboard wipe) SHALL be defined only in files under `i3/risky-utilities/`, and SHALL NOT be included by `i3/config`'s `include conf.d/*.conf` directive or any other automatic mechanism.

#### Scenario: Fresh install does not wire in risky utilities
- **WHEN** a user runs `install.sh` on a machine with only `i3` + `i3-settings-qubes` installed
- **THEN** none of the brightness/playback/screenshot/recording/nightlight/color-picker/clipboard-wipe binds are active, and `i3 -C -c i3/config` reports no error related to missing packages for these features

#### Scenario: User opts into a risky-utilities feature later
- **WHEN** a user wants the brightness OSD after installing the required package (`brightnessctl`)
- **THEN** they either add an `include risky-utilities/risky_media.conf` line to `i3/config`, or copy the relevant section from `i3/risky-utilities/risky_media.conf` into a file under `conf.d/`

### Requirement: A feature already covered by the Qubes baseline belongs in the active config
A feature SHALL NOT be held in `i3/risky-utilities/` on dependency grounds if the official `i3-settings-qubes` config already binds the same keys to the same underlying tool, since that tool is then part of the dom0 baseline by definition.

#### Scenario: Volume and mic-mute keys
- **WHEN** someone checks where the `XF86AudioRaiseVolume`/`XF86AudioLowerVolume`/`XF86AudioMute`/`XF86AudioMicMute` binds live
- **THEN** they are in the active config (`i3/conf.d/30-apps.conf`), not in `risky-utilities/`, because upstream binds those same keys to `pactl` directly — and `risky_media.conf` records why they moved

### Requirement: Risky-utilities files follow a `risky_` naming convention
Every file under `i3/risky-utilities/` SHALL be named `risky_<name>.conf`, and SHALL carry a header comment stating that it is reference/copy-paste-only and listing the extra package(s) each bind group requires.

#### Scenario: Adding a new deferred feature later
- **WHEN** a new hardware/utility feature is proposed for this config in the future
- **THEN** its config lives at `i3/risky-utilities/risky_<name>.conf` with a header comment naming its package dependencies, keeping the active/reference boundary visually consistent with existing entries (`risky_media.conf`, `risky_clipboard.conf`)
