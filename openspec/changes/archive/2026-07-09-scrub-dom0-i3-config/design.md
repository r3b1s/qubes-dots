## Context

`x11-dots` was migrated from an omarchy/hyprland keybinding set (see `AGENTS.md` /
README's "Key migration decisions") and, until now, kept every omarchy-era
app-launching bind intact — just re-targeted at i3 syntax. It's installed via
`install.sh` symlinking `i3/` and `dunst/` into `~/.config/` and `bin/*` into
`~/.local/bin/` in **dom0** on Qubes OS 4.3.1. The user has confirmed only the
official `i3` and `i3-settings-qubes` packages are installed there, and wants
that to remain the entire package requirement for the active config.

Researching upstream ([`qubes-desktop-linux-i3-settings-qubes`](https://github.com/QubesOS/qubes-desktop-linux-i3-settings-qubes))
confirmed dunst and i3lock/xss-lock are already part of the stock qubes i3
setup (started by `i3-settings-qubes`'s own config), so this repo's dunst
config and lock bind are not adding to the package list. `dmenu` and `jq` are
already covered by dom0's default packages per the user, so neither is called
out as an extra requirement anywhere in this change.

## Goals / Non-Goals

**Goals:**
- Zero desktop applications launched directly in dom0 by this config.
- The active (`i3/conf.d/`-included) config has no package dependency beyond
  `i3` + `i3-settings-qubes`.
- App-launching functionality is preserved, redirected through `qvm-run` into
  named AppVMs, with VM names centralized and easy to edit.
- Hardware/utility conveniences that need extra packages are preserved as
  copy-paste reference, not deleted outright, but are structurally excluded
  from the default install.

**Non-Goals:**
- Auto-detecting or auto-creating the AppVMs referenced by
  `70-qube-apps.conf` — the user fills in real VM names themselves.
- Wiring any `risky-utilities/risky_*.conf` file into the active config by
  default — that's an explicit, separate opt-in the user performs later.
- Reproducing `i3-settings-qubes`'s own per-domain workspace coloring (out of
  scope for this change; a separate concern from app-launch/attack-surface
  scrubbing).

## Decisions

- **Repoint via `qvm-run -a "$vm" -- <command>` rather than deleting
  app-launch binds outright.** The user explicitly asked to keep the
  functionality (workspace-toggle UX, named workspaces, `assign` rules) but
  move the actual process boundary into an AppVM. `-a` auto-starts the VM if
  it isn't running, matching the existing "launch on empty workspace"
  behavior of `x11-ws-app`.
- **One consolidated `i3/conf.d/70-qube-apps.conf` instead of scattering
  qvm-run binds back into `20-workspaces.conf`/`30-apps.conf`/
  `40-modes.conf` in place.** The user asked for this explicitly: a single
  file with a variables block at the top is easier to audit and edit than
  qvm-run calls scattered across three files with unrelated concerns.
- **`qvm-run -a "$vm_browser" -- xdg-open "<url>"` instead of porting
  `x11-webapp`'s browser-detection loop across the qube boundary.** The
  target VM's own `xdg-open` already knows its installed default browser;
  duplicating `x11-webapp`'s chromium-family detection loop remotely would
  require guessing what's installed in a VM this repo doesn't control.
  Trade-off: loses the "always open as an app window" (`--app=`) behavior
  `x11-webapp` provided — accepted, since that's a cosmetic omarchy touch,
  not core functionality.
- **`i3/risky-utilities/` is a plain directory outside `conf.d/`, not a
  single file, with each file prefixed `risky_`.** `include conf.d/*.conf`
  only globs `conf.d/`, so anything outside it is inert by construction —
  no risk of an editor accidentally re-globbing it in. The `risky_` prefix
  (rather than relying on directory location alone) keeps the active/
  inactive distinction visible even if a file gets copied elsewhere later.
- **`btop` → `top`, kept rather than dropped.** Per user correction: a
  system-monitor terminal is reasonable dom0-native functionality, and `top`
  ships with dom0 by default, so this preserves the bind's intent (`$mod+p`,
  toggle a monitoring terminal) at zero package cost — unlike `lazydocker`,
  `easyeffects`, `nmtui`, `bluetui`, which have no dom0-native equivalent
  because dom0 doesn't run docker/audio-effects/own network or Bluetooth
  hardware.
- **`assign` rules for repointed apps are unchanged.** Qubes' GUI
  virtualization surfaces a VM-run application's window in dom0's X session
  with that application's own `WM_CLASS`, identical to a locally-run
  instance — so i3 `assign` rules keyed on class continue to work whether
  the process is local or in a VM.

## Risks / Trade-offs

- [Risk] `70-qube-apps.conf` ships with placeholder VM names; until the user
  edits them, every app-launch bind will either error out (`qvm-run` against
  a nonexistent VM) or launch into the wrong VM. → Mitigation: placeholder
  names are obviously fake (e.g. `personal-browsing`) and the file's header
  comment calls out that editing this block is required before use; this is
  also the last item in `tasks.md`'s verification task.
- [Risk] Losing `x11-webapp`'s "open as app window" (`--app=`) behavior for
  webapp shortcuts means those windows now open as regular browser tabs/
  windows inside the target VM rather than chromeless app windows. →
  Mitigation: acceptable cosmetic regression per design decision above; the
  user can still pass an equivalent flag directly in `70-qube-apps.conf`'s
  qvm-run command if they want it back for a specific VM's browser.
- [Risk] This local (non-Qubes) sandbox can syntax-check the merged i3
  config but cannot exercise `qvm-run`, verify AppVM names, or confirm
  `i3-settings-qubes` compatibility. → Mitigation: verification task is
  explicit about this limit and defers real-world exercise to the user on
  the actual dom0 machine.

## Migration Plan

1. Apply the file changes described in `tasks.md`.
2. Locally: install `i3` + `xorg-x11-server-Xvfb`, run
   `xvfb-run -a i3 -C -c i3/config` to confirm the merged config parses.
3. On the user's real Qubes dom0: `git pull` (or re-copy) the repo, re-run
   `install.sh` (idempotent, backs up any non-symlink target), edit the
   `$vm_*` variables in `70-qube-apps.conf` to real AppVM names, then
   `i3-msg reload`.
4. Rollback: `install.sh` already backs up any pre-existing non-symlink
   `~/.config/i3` / `~/.config/dunst` to a timestamped `.bak`; reverting is
   `git revert` on this change plus re-running `install.sh`, or restoring
   the `.bak` directory if the user prefers not to touch git history on the
   dom0 machine.

## Open Questions

- Should `70-qube-apps.conf`'s placeholder VM names map 1:1 to a suggested
  qube-creation script (e.g. `qvm-create personal-browsing ...`), or is
  documenting the expected names in README enough? Left as README
  documentation only for this change; can be revisited if the user wants a
  bootstrap script later.
