# qubes-dots

i3wm + dmenu + dunst + i3lock config for **dom0** on Qubes OS.

Dom0 is meant to stay free of untrusted application code, so the active
config launches no desktop applications locally: every app keybind runs its
application inside a named AppVM through `qvm-run`, and anything needing a
package beyond the dom0 baseline is kept out of the loaded config entirely.

## Initial install

Paste this into a dom0 terminal to install git, clone this repo (and any
others you list) into `/home/user/Dotfiles` on your `personal` AppVM, then pull
the whole `Dotfiles` directory back into dom0 — see `dom0-clone-dots.sh` for
the equivalent script form:

```bash
VM=personal; DOTS=/home/user/Dotfiles; CLONE_TARS="https://github.com/r3b1s/qubes-dots"; qvm-run --pass-io "$VM" "sudo dnf install -y git" && qvm-run --pass-io "$VM" "mkdir -p $DOTS" && IFS=',' read -ra U <<< "$CLONE_TARS" && for u in "${U[@]}"; do qvm-run --pass-io "$VM" "git -C $DOTS clone '$u'"; done && qvm-run --pass-io "$VM" "tar -cf - -C $(dirname "$DOTS") $(basename "$DOTS")" | tar -xf - -C "$HOME"
```

Edit `CLONE_TARS` to your own repo URL(s) first. Then run `./install.sh`
from the cloned copy in dom0.

## Layout

```
i3/config          entry point: variables + the conf.d include
i3/monitor.conf    display layout: resolution, refresh rate, arrangement
i3/conf.d/         modules loaded via i3's `include` — always active
  00-qubes-base.conf  vendored Qubes defaults: VM label colours, autostart
  05-monitors.conf    applies monitor.conf through bin/x11-monitor
  10-core.conf     general settings, focus / move / resize / layouts / floating
  15-bar.conf      the i3bar: upstream's block, moved here and pinned to the top
  20-workspaces.conf  numbered + named workspaces, window routing
  30-apps.conf     launchers, terminals, dunst binds, volume keys
  40-modes.conf    gaps / passthru modes
  70-qube-apps.conf   AppVM name variables + every app-launching bind
i3/risky-utilities/   reference only, never auto-included
  risky_media.conf     brightness, playback, nightlight, capture
  risky_clipboard.conf color picker, clipboard wipe
bin/               helper scripts (x11-* prefix), symlinked to ~/.local/bin
dunst/dunstrc      notifications
install.sh         symlinks everything into place (user-agnostic, re-runnable)
kanata/            dom0 kanata (enthium layout); run install-kanata-dom0.sh in dom0 — not part of i3

qrexec/            the dom0 dev shell — see "Developing against dom0"
  dev.Shell           qrexec service, installed to /etc/qubes-rpc/ in dom0
  30-dev-shell.policy policy template; @DEV_VM@ is substituted at install time
dom0-install-devshell.sh  installs both of the above (run in dom0, once)
dom0sh             runs a command in dom0 over qrexec (run in the dev qube)
install-dom0sh.sh  symlinks dom0sh into ~/.local/bin (run in the dev qube)
dom0-clone-dots.sh clones this repo into an AppVM, tars it into dom0  (bootstrap)
dom0-sync-dots.sh  re-pulls it and swaps the tree in                  (iterate)
dom0-push-dots.sh  reverse: copies dom0 dirs back out to an AppVM, optional git push
```

## Layering on the Qubes defaults

`install.sh` symlinks `i3/` over `~/.config/i3`, and i3 reads
`~/.config/i3/config` *instead of* `/etc/i3/config` — never both. Qubes ships
its config **as** `/etc/i3/config`, so nothing from the `i3-settings-qubes`
package reaches us implicitly. `conf.d/00-qubes-base.conf` carries the parts
of it we keep, verbatim, and sorts first in the glob.

That ordering is load-bearing, because i3's override rules are not uniform:

| Directive | On conflict |
| --- | --- |
| `bindsym` / `bindcode` | **first** wins; duplicates are a config error |
| `bar { }` | **first** wins, even with a matching `id` |
| `exec` / `exec_always` | accumulate; cannot be removed |
| `font`, `gaps`, `client.*`, `focus_follows_mouse` | **last** wins |
| `for_window`, `assign` | accumulate |

i3 has no `unbindsym` (that is a sway directive), so a later `bindsym` can
never override an earlier one. Our modules therefore never redeclare a bind
that `00-qubes-base.conf` already declares — they only override scalar
settings, which the base file's header lists explicitly.

The `bar` block is the one thing that rule cannot accommodate: it is neither
overridable nor removable from a later file, so wanting `position top` meant
moving it out of the vendored copy entirely. It now lives, otherwise verbatim,
in `conf.d/15-bar.conf`, and it is the only `bar` block in the config.

Re-check the vendored copy whenever `i3-settings-qubes` updates — the missing
`bar` block is the one hunk you should expect:

```sh
diff <(sed -n '/## VARS BEGIN/,$p' /etc/i3/config) i3/conf.d/00-qubes-base.conf
```

### What the baseline gives us

Beyond the bar and the autostart execs, the pieces worth naming:

- **VM label colours.** The 45 `client.<label>` lines are a Qubes patch to i3;
  stock i3 rejects them outright. They colour each window's border by the
  owning qube's label. Borders stay at i3's `normal` so the titlebar keeps
  showing the qube name — together those are Qubes' window trust indicator,
  which is why there is no border-width bind.
- **`qubes-i3-sensible-terminal`.** `$mod+Shift+t` opens a terminal in the
  domain of the *focused window*, not a dom0 shell; `$mod+Shift+Return` opens
  a disposable console into it.
- **`qubes-app-menu`** on `$mod+Shift+d`, and `j4-dmenu-desktop` on
  `$mod+Return` with upstream's exact arguments — `--term=` is what makes a
  terminal-type `.desktop` entry open inside its own qube.
- **`qubes-i3-xdg-autostart`**, which upstream notes is needed for transient
  VMs to come up.
- **Tor Browser floats** by title, to avoid screen-size fingerprinting, and
  `zenity` dialogs float rather than tiling into the layout.

## Install

```sh
./install.sh
```

Required: `i3`, `i3-settings-qubes`, and `feh`.

```sh
sudo qubes-dom0-update i3 i3-settings-qubes feh
```

Between the first two (plus dom0's own default packages) they supply `dmenu`,
`j4-dmenu-desktop`, `dunst`, `i3lock`, `xss-lock`, `pactl`, `jq`, `qvm-run`,
`qubes-app-menu`, and the `qubes-i3status` / `qubes-i3-sensible-terminal` /
`qubes-i3-xdg-autostart` helpers. `feh` sets the desktop wallpaper
(`wallpapers/cube-bg.png` via `conf.d/05-monitors.conf`). Beyond that, the
active config is held to this baseline deliberately: no bind may need a package
you'd otherwise have no reason to install in dom0. `bin/x11-monitor` uses
`xrandr`, which dom0 already ships.

### Monitors and refresh rate

i3 does no mode-setting, so resolution and refresh rate are xrandr's job.
`i3/monitor.conf` describes the layout declaratively — it is the stand-in for
hyprland's `monitor=` lines — and `conf.d/05-monitors.conf` applies it through
`bin/x11-monitor` on every startup and reload.

The shipped default needs no editing and names no output:

```
*,preferred,highest,auto
```

`preferred` is the resolution xrandr marks `+`, which is the panel's native
one; `highest` is the fastest refresh rate that resolution offers. A 144 Hz
monitor therefore comes up at 144 Hz on its own — this is hyprland's
`monitor=,preferred,highrr,auto`. `auto` puts the first output at `0x0` and
each subsequent one to its right.

Override per output by naming it, in `<output>,<resolution>,<rate>,<position>,<flag>`:

```
DP-1,2560x1440,144,0x0,primary
HDMI-1,preferred,60,left-of DP-1
eDP-1,off
```

Rates match within 1 Hz, so writing `144` finds the mode xrandr calls
`143.91`; you never have to copy decimals out of `xrandr --query`. A rate the
output cannot do is an error rather than a silent fall back to 60 Hz. Position
also takes `right-of` / `above` / `below` / `same-as <output>`, the last of
which mirrors.

The script skips xrandr entirely when the outputs already match, so an
`i3-msg reload` does not flash the screen. After editing `monitor.conf`,
reload i3, or run `x11-monitor -f` to force a re-apply.

### Pointing the app binds at your AppVMs

Every application keybind lives in `i3/conf.d/70-qube-apps.conf` and runs
through `qvm-run -a "$vm_…" -- <command>`. The file opens with a block of VM
names:

```
set $vm_default personal0
set $vm_browser $vm_default
set $vm_chat $vm_default
set $vm_vault $vm_default
set $vm_notes $vm_default
set $vm_media $vm_default
set $browser_bin_firefox firefox
set $browser_bin_brave  brave-origin
```

**These are placeholders.** Edit them to match your real AppVMs (and the
browser binary as it's named inside `$vm_browser`) before the app binds do
anything but produce `qvm-run` errors. No other file needs to change.

Windows opened this way still report their application's own `WM_CLASS`
through Qubes' GUI virtualization, so the `assign` rules in the same file
route them to the right workspace exactly as a local process would.

### Opting into a risky utility

Volume/brightness OSD, screenshots, screen recording, nightlight, the color
picker, and clipboard wipe each need packages beyond the baseline, so they
ship inert under `i3/risky-utilities/` as `risky_<name>.conf`. That
directory sits outside `conf.d/`, so `include conf.d/*.conf` can never pick
it up by accident.

To enable one: install its packages (each file's header lists them), then
either add an explicit `include risky-utilities/risky_media.conf` line to
`i3/config`, or copy the section you want into a file under `conf.d/`.

## Updating dom0 from your repo

`dom0-clone-dots.sh` is the bootstrap — the first clone. `dom0-sync-dots.sh` is
what you run the twentieth time. Both are plain dom0 scripts: run them from a
dom0 terminal as your normal user, no root and no extra setup.

```sh
# in dom0
~/Dotfiles/qubes-dots/dom0-sync-dots.sh qubes-dots <source-vm> --install --reload
```

It runs `git pull --ff-only` inside the source AppVM, tar-copies the result
back into `~/Dotfiles`, then optionally re-runs that folder's `install.sh` and
reloads i3. git stays in the AppVM; dom0 needs neither git nor a network
interface. Sync several repos at once by comma-separating them, as with
`dom0-push-dots.sh`.

Sync is **one-way and wholesale**. Each folder is extracted beside the old one
and swapped in, so a file deleted upstream disappears in dom0 too, and local
edits under dom0's `~/Dotfiles/<folder>` are destroyed. Edit in the AppVM and sync
down; to go the other way, that is `dom0-push-dots.sh`. The swap happens only
after the new tree lands whole, so an interrupted transfer leaves dom0's copy
as it was rather than half-replaced.

Because it pulls, dom0 sees only what you have **committed and pushed**.
`--dirty` skips the pull and copies the AppVM's working tree as it stands,
which is convenient while you are hand-editing.

## Developing against dom0

Everything above stands on its own — skip this section entirely unless you want
an agent, or anything else with a network connection, driving dom0.

Dom0 has no network interface — not firewalled, absent — so there is no SSH
into it and never will be. The supported channel is qrexec, which is what
`dom0-clone-dots.sh` and `dom0-push-dots.sh` already use to move files.

That covers file transfer. What it does not cover is *iterating*: writing a
dom0 provisioning script somewhere with network and tooling, running it in
dom0, and reading back what went wrong. `qrexec/dev.Shell` closes that gap. It
is a dom0 service that reads a shell script on stdin, runs it, and streams
stdout, stderr and exit status back to the calling qube.

Install the dom0 half once, after `dom0-clone-dots.sh` has landed the repo:

```sh
# in dom0
~/Dotfiles/qubes-dots/dom0-install-devshell.sh <your-dev-qube>
```

Then the caller half, in the dev qube named above:

```sh
./install-dom0sh.sh
dom0sh 'qvm-ls --raw-data --fields NAME'
dom0sh < provision-work-vm.sh
```

`dom0-install-devshell.sh --uninstall` removes both files from dom0.

### Driving the sync from the dev qube

`dev.Shell` runs *commands* in dom0; it does not update the *files* there. That
is [`dom0-sync-dots.sh`](#updating-dom0-from-your-repo), the same script you
would run from a dom0 terminal, called through `dom0sh`:

```sh
dom0sh '/home/user/Dotfiles/qubes-dots/dom0-sync-dots.sh qubes-dots dev --install --reload'
```

Note the absolute path: `dev.Shell` runs as root, so `~` there is `/root`, not
your dom0 home. The script notices it is running as root and re-execs itself as
the desktop user, so this lands where a dom0 terminal would put it. If your
dom0 account is not named `user`, set `QUBES_USER` — and fix the path above.

Prefer the default (pull, not `--dirty`) on this path. Dom0 then only ever sees
what you have committed and pushed, and the commit is the only place you get to
look at what you are about to run in dom0.

### What this actually grants

An unrestricted root shell in dom0, to one named qube, with no prompt. Dom0
owns the hypervisor, the GUI, and every qube's disk, so this is total authority
over the machine. It is the same capability `sshd` in dom0 would grant, minus
the network interface and minus OpenSSH's attack surface — the exposed code is
the twenty lines of `qrexec/dev.Shell` — but it is not *less* authority.

Two properties are worth stating rather than discovering:

- **`allow` means unattended.** Anything that reaches the dev qube reaches
  dom0. If an agent runs there, then a web page it fetched or a repo it read
  can reach dom0 too. Install with `--ask` to require a dom0 confirmation per
  call; the prompt becomes muscle memory within a day, which is a real limit on
  how much it buys you, but it is the difference between a mistake and an
  unattended one.
- **Services run as root**, so `$HOME` is `/root` and there is no `DISPLAY`.
  `install.sh` under `dom0sh` would symlink into root's home, not yours. Wrap
  anything user- or X11-facing:

  ```sh
  dom0sh 'runuser -u user -- env DISPLAY=:0 i3-msg reload'
  ```

The intended home for this is a test machine. It will work identically on a
real one, which is the hazard: nothing about it will feel wrong there.


## Notes

- `assign` rules route app windows to their named workspaces; X11 `WM_CLASS`
  values vary by packaging — verify with `xprop WM_CLASS` and adjust in
  `70-qube-apps.conf`.
- `$mod+Alt+t` opens a terminal in this repo by resolving the `~/.config/i3`
  symlink, so it works wherever the repo is cloned.
