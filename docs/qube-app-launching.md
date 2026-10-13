## Purpose

Ensure every user-facing application keybind launches inside a named AppVM via `qvm-run`, with VM targets centralized in a single, user-editable variable block.

## Requirements

### Requirement: Application keybinds launch inside a named AppVM
Every keybind that opens a user-facing application (browser, chat client, password manager, notes app, media app, or a webapp shortcut) SHALL launch that application via `qvm-run` targeting a named AppVM, not as a local dom0 process.

#### Scenario: Launching a browser via its keybind
- **WHEN** the user presses a browser-launch keybind (e.g. `$mod+u`, `$mod+b`)
- **THEN** i3 runs `qvm-run -a "$vm_browser" -- <browser-command>` (or equivalent), and the resulting window — reporting the browser's own `WM_CLASS` through Qubes' GUI virtualization — is routed to the expected workspace by the existing `assign` rules

#### Scenario: Launching a webapp shortcut
- **WHEN** the user presses a webapp keybind (e.g. the ChatGPT/Claude/calendar/email/dictionary/gitlab shortcuts)
- **THEN** i3 runs `qvm-run -a "$vm_browser" -- xdg-open "<url>"`, letting the target VM's own `xdg-open` pick its default browser

#### Scenario: Toggling a named workspace with launch-on-empty
- **WHEN** the user presses a workspace-toggle keybind (e.g. `$mod+comma` for `signal`) and that workspace has no windows yet
- **THEN** `x11-ws-app` switches to the workspace and runs `qvm-run -a "$vm_x" -- <command>` for the target VM, exactly mirroring the existing empty-workspace launch behavior but with the command executed inside the VM instead of dom0

### Requirement: AppVM targets are centralized and editable
The VM names used by app-launching binds SHALL be defined as a single block of i3 `set` variables at the top of one file, not hardcoded inline at each bind site.

#### Scenario: User adapts the config to their own AppVM naming
- **WHEN** a user installs this config and wants to point browser/chat/vault/notes/media launches at their own AppVMs
- **THEN** they edit only the `set $vm_*` variable block at the top of `i3/conf.d/70-qube-apps.conf` — no other file needs to change

### Requirement: Browser-profile switching launches inside the browser AppVM
The browser-profile mode SHALL launch each profile/incognito/private variant via `qvm-run` into the configured browser AppVM, preserving the existing profile-selection UX.

#### Scenario: Selecting a numbered profile from the browser-profiles mode
- **WHEN** the user enters the `browser-profiles` mode and selects a profile key
- **THEN** i3 runs `qvm-run -a "$vm_browser" -- <browser> --profile-directory='Profile N'` (or the incognito/private-tmp/system-profile variant) inside the browser AppVM, and the mode exits back to `default`
