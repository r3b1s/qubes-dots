# Dom0 desktop integration tools

The Qubes-specific binaries our i3 config and `bin/` scripts actually
invoke. All of them come from `qubes-desktop-linux-*` packages (installed
via `sudo qubes-dom0-update <pkg>` in dom0) and only make sense in dom0:
this is where the GUI domain lives and where raw input devices are read.

Repo-relevant set, mapped to where we use them:

| Tool | Package origin | Where we use it |
|---|---|---|
| `qubes-i3status` | `qubes-desktop-linux-i3` (`i3-settings-qubes`) | `i3/conf.d/15-bar.conf` `status_command` |
| `qubes-i3-sensible-terminal` | `qubes-desktop-linux-i3` | `$terminal`/`$console` vars in `00-qubes-base.conf` |
| `qubes-i3-xdg-autostart` | `qubes-desktop-linux-i3` | `$desktop_autostart` var, exec'd at startup |
| `qubes-input-sender` | `qubes-core-dom0` | keyboard/mouse injection to `sys-usb` (`qubes.InputKeyboard` RPC) |
| `qvm-appmenus` | `qubes-desktop-linux-common` | app-menu generation behind `$mod+d` entries |
| `j4-dmenu-desktop` / `i3-dmenu-desktop` | third-party / upstream | our `$dmenu` launcher |

## What each does

### `qubes-i3status` — domain-aware i3bar

Wrapper around `i3status` that appends Qubes fields (qube count, disk usage
per pool) to the status line. It's why `i3/conf.d/15-bar.conf` sets
`status_command qubes-i3status` instead of plain `i3status` — plain
i3status knows nothing about qubes.

### `qubes-i3-sensible-terminal` — default terminal pick

Qubes' wrapper that finds a sensible installed terminal emulator. Our
`00-qubes-base.conf` sets `$terminal` to it (and `$console` to
`qubes-i3-sensible-terminal console`); `10-core.conf` exists partly because
this baseline wrapper is pickier about flags than a hand-picked terminal.

### `qubes-i3-xdg-autostart` — XDG autostart in dom0

Runs the standard XDG autostart sequence for dom0 so `.desktop` entries in
`/etc/xdg/autostart` still fire under i3 (Qubes uses it to bring up
tray/applets). Vendored into the baseline as `$desktop_autostart`.

### `qubes-input-sender` — trusted input injection

Dom0-side helper for the USB keyboard/mouse qubes: when a raw input device
is attached to `sys-usb`, dom0 runs `qubes-input-sender-keyboard@<device>`
/ `...-mouse@<device>` services, which read the real device in dom0 and
forward events over the `qubes.InputKeyboard` / `qubes.InputMouse` qrexec
RPC into the target qube. dom0 stays the trust boundary; the USB qube
handles only the untrusted hardware side.

Relevance: `docs/kanata-sys-usb.md` plans to replace
`qubes-input-sender` for keyboard nodes whose device is a Kanata virtual
device (Vendor `0001`), while leaving real devices on the stock binary.

### `qvm-appmenus` — menu entry cache

Manages the `.desktop` entries and icons dom0 caches for each qube; the
app-menu lists (and thus our `j4-dmenu-desktop` entries) are built from
this cache.

```console
[user @dom0 ~]$ qvm-appmenus --update work        # refresh after template change
[user @dom0 ~]$ qvm-appmenus --init --source fedora-41 new-vm
[user @dom0 ~]$ qvm-appmenus --set-whitelist - work   # whitelist via stdin
```

- `--update` regenerates entries (for templates, also their children);
  `--init` sets up a new qube's menu directory; `--set-whitelist` limits
  which apps are advertised.

### `qvm-xkill` — kill a wedged qube window

```console
[user @dom0 ~]$ qvm-xkill
```

Click a window to kill its `qubes-guid` (the dom0-side window stub for that
qube). Clicking a non-Qubes window does nothing and cancels. Docs suggest
pairing `qvm-pause --all` + `qvm-xkill` on shortcuts as the escape hatch
for a GUI denial-of-service from a misbehaving qube.

## Installation context

All of the above arrive through the dom0 package channel — never install
them by hand:

```console
[user @dom0 ~]$ sudo qubes-dom0-update i3 i3-settings-qubes
```

`i3-settings-qubes` (upstream `/etc/i3/config`) is what
`conf.d/00-qubes-base.conf` vendors. The Qubes i3 integration, including
the colored-border patch that makes titlebars show the qube name and label
colours, is part of `qubes-desktop-linux-i3`; see the upstream doc
`user/advanced-topics/i3.rst` in the qubes-doc clone.
