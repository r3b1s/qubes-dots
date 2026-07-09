## 1. New qube-apps config

- [x] 1.1 Create `i3/conf.d/70-qube-apps.conf` with a `set $vm_*` variables block (`$vm_browser`, `$vm_chat`, `$vm_vault`, `$vm_notes`, `$vm_media`) at the top, using obviously-placeholder VM names.
- [x] 1.2 Move `browser1`/`browser2`, `signal`, `discord`, `obsidian`, `grayjay`, `moonlight`, `bitwarden`, `keepassxc`, `cryptomator`, and the `llm`/`dictionary`/`gitlab`/`calendar`/`email` webapp workspace binds from `i3/conf.d/20-workspaces.conf` into `70-qube-apps.conf`, repointing each through `qvm-run -a "$vm_x" -- <command>` (workspace-toggle binds: `$bin/x11-ws-app <ws> qvm-run -a "$vm_x" -- <command>`).
- [x] 1.3 Move the corresponding `assign [class=...]` rules for those apps from `20-workspaces.conf` into `70-qube-apps.conf` unchanged.
- [x] 1.4 Move `$mod+b`/`$mod+Shift+b`/`$mod+Ctrl+b` browser binds, `$mod+Shift+o` obsidian, `$mod+Shift+m` grayjay, and the perplexity/claude/chatgpt/calendar/email webapp binds from `i3/conf.d/30-apps.conf` into `70-qube-apps.conf`, repointed through `qvm-run`; webapp binds use `qvm-run -a "$vm_browser" -- xdg-open "<url>"`.
- [x] 1.5 Move the entire `browser-profiles` mode from `i3/conf.d/40-modes.conf` into `70-qube-apps.conf`, repointing each `exec $browser ...` line through `qvm-run -a "$vm_browser" -- <browser> <flags>`.

## 2. Trim the active workspace/app/mode configs

- [x] 2.1 In `i3/conf.d/20-workspaces.conf`, remove the `lazydocker`, `easyeffects`+`wiremix`, `wifi`(nmtui), `bluetooth`(bluetui) workspace binds entirely.
- [x] 2.2 In `i3/conf.d/20-workspaces.conf`, rename the `btop` workspace bind to `top`, changing `$term -e btop` to `$term -e top`.
- [x] 2.3 In `i3/conf.d/30-apps.conf`, remove the `nautilus`, `$mod+Ctrl+t` tmux-sessionizer, `~/.cargo/bin/inputbox`, `gnome-calculator`, and `$mod+Alt+p` btop-terminal binds.
- [x] 2.4 In `i3/conf.d/40-modes.conf`, confirm only `gaps` mode and `passthru` mode remain after the `browser-profiles` mode is moved out (task 1.5).

## 3. Risky-utilities reference files

- [x] 3.1 Create `i3/risky-utilities/risky_media.conf` containing the full former contents of `i3/conf.d/50-media.conf` (volume, brightness, playback, nightlight, screenshot, screen recording), with a header comment marking it reference/copy-paste-only and noting required packages (`pactl`, `brightnessctl`, `playerctl`, `redshift`, `maim`+`xclip`, `ffmpeg`+`xdpyinfo`).
- [x] 3.2 Create `i3/risky-utilities/risky_clipboard.conf` containing the color-picker (`xcolor`) and clipboard-wipe (`xclip`) binds moved from `i3/conf.d/30-apps.conf`, with the same style of header comment (required packages: `xcolor`, `xclip`).
- [x] 3.3 Delete `i3/conf.d/50-media.conf`.

## 4. Cleanup

- [x] 4.1 Delete `bin/x11-webapp` (no longer referenced after task 1.4/1.5).
- [x] 4.2 Remove `set $browser` from `i3/config`.

## 5. Documentation

- [x] 5.1 Rewrite README.md's "Required"/"Per-feature" sections: baseline is `i3` + `i3-settings-qubes` only; document the `70-qube-apps.conf` VM-variable pattern and the `risky-utilities/risky_*.conf` reference-file pattern (how to opt in via `include` or copy-paste).
- [x] 5.2 Add `lazydocker`/`easyeffects`/`nmtui`/`bluetui` to README's existing "Intentionally dropped" section, matching its existing convention.
- [x] 5.3 Update README's layout diagram to reflect `70-qube-apps.conf` and `risky-utilities/`.
- [x] 5.4 Add a convention note to AGENTS.md: `conf.d/` is always-on; `risky-utilities/risky_*.conf` is copy-paste-only and must never be glob-included or wired into `i3/config` by default.

## 6. Verification

- [x] 6.1 `sudo dnf install -y i3 xorg-x11-server-Xvfb` locally (headless sandbox).
- [x] 6.2 `xvfb-run -a i3 -C -c i3/config` (fallback: `Xvfb :99 -screen 0 1x1x24 & DISPLAY=:99 i3 -C -c i3/config`) — confirm the merged config parses with no syntax errors.
- [x] 6.3 `grep -rn 'x11-webapp\|\$browser\b' i3/ bin/` — confirm no dangling references to the deleted helper/variable remain.
- [x] 6.4 `grep -rn 'lazydocker\|easyeffects\|nmtui\|bluetui\|nautilus\|inputbox\|gnome-calculator\|tmux-sessionizer' i3/conf.d/` — confirm none of the dropped ceremony remains in the active config set.
- [x] 6.5 Note in the PR/change notes that `i3-settings-qubes`, `qvm-run`, and real AppVM names aren't available in this sandbox — flag for the user to sanity-check one repointed bind (e.g. `$mod+u` bringing up the configured `$vm_browser` AppVM on the `browser1` workspace) on the real Qubes dom0 machine after filling in `70-qube-apps.conf`'s VM variables.

## Notes for the reviewer / dom0 sanity check

Verification 6.1–6.4 ran in a local non-Qubes sandbox. `xvfb-run -a i3 -C -c
i3/config` parses the merged active config with no errors, and the greps
confirm no dangling `x11-webapp`/`$browser` references and no dropped
ceremony left in `i3/conf.d/`.

What the sandbox **cannot** check: `i3-settings-qubes` isn't installed here,
`qvm-run` doesn't exist, and no AppVMs exist to target. After pulling this
onto the real dom0 and filling in `70-qube-apps.conf`'s `$vm_*` variables,
please sanity-check at least one repointed bind end to end — e.g. `$mod+u`
should auto-start the configured `$vm_browser` AppVM and land its browser
window on the `browser1` workspace via the `assign` rule.
