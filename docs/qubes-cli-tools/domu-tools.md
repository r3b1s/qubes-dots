# DomU tools (run *inside* a qube)

The mirror image of [qvm-admin-tools.md](qvm-admin-tools.md): these are
shipped by the *agent* packages (`qubes-core-agent-linux`,
`qubes-core-qrexec`) inside every Linux qube — templates, standalones,
disposables. They are how an unprivileged qube reaches out to the rest of
the system without ever holding real power. **They do not exist in dom0.**

## File and URL transfer

### `qvm-copy` / `qvm-move` — send files to another qube

```console
[user@work ~]$ qvm-copy --without-progress file1 file2
[user@work ~]$ qvm-move notes.txt
```

- Prompt for the destination qube (dmenu-style picker); files land in
  `/home/user/QubesIncoming/<source-vm>/`.
- `qvm-move` = copy + delete local original.
- Explicit-destination scripting variants `qvm-copy-to-vm` /
  `qvm-move-to-vm` are **deprecated outside dom0**; in dom0 they are still
  the way to push a file out (`qvm-copy-to-vm <target_vm> <file>`).
- Both are policy-gated: every transfer is a `qubes.FileCopy` qrexec call
  that dom0's policy may allow, deny, or turn into a prompt.

### `qvm-open-in-vm` / `qvm-open-in-dvm` — hand off a file or URL

```console
[user@work ~]$ qvm-open-in-vm work-browser https://example.com
[user@work ~]$ qvm-open-in-vm suspicious.pdf        # policy picks target
[user@work ~]$ qvm-open-in-dvm -- 'untrusted.pdf'   # always a disposable
```

- `qvm-open-in-vm [vmname] <file|URL>`: without a vmname it sends
  `@default`, and the qrexec policy decides where the file actually lands —
  useful to make destinations policy-controlled rather than hardcoded.
- `qvm-open-in-dvm <file|URL>`: spins up (or reuses a preloaded) disposable
  so untrusted content never touches your persistent qubes.
  `--view-only` for read-only rendering. Also usable as an `xdg` handler
  (e.g. `xdg-settings set default-web-browser qvm-open-in-dvm.desktop`).

## Running commands from inside a qube

### `qvm-run-vm` — the domU-side qvm-run

```console
[user@work ~]$ qvm-run-vm backup-vm 'tar cf - /home/user' | tar xf -
[user@work ~]$ qvm-run-vm --dispvm xterm
```

- `qvm-run-vm vmname command [args...]`; pass `--dispvm` in place of a
  vmname to target a fresh disposable.
- This is the same idea as dom0's `qvm-run` but callable from a qube. It
  cannot start arbitrary stopped qubes like dom0's can — expect policy to
  gate the `qubes.VMShell` call underneath.

## Trusted converters

### `qvm-convert-pdf` / `qvm-convert-img` / `qvm-convert-file`

```console
[user@work ~]$ qvm-convert-pdf --in-place scan.pdf
[user@work ~]$ qvm-convert-pdf --ocr-lang eng suspicious.pdf
```

- Sends the file to a disposable that renders each page to a bitmap and
  returns a *reconstructed* PDF: any embedded exploit is destroyed, at the
  cost of text layer and structure (OCR can re-add searchable text,
  `--ocr-lang`).
- Useful flags: `--in-place/-i`, `--archive/-a DIR` (keep originals),
  `--resolution/-r` (75–4800 ppi, default 300), `--password/-p`,
  `--batch/-b N`.
- `qvm-convert-img` does the same for images; `qvm-convert-file` covers
  DOCX/ODT/XLSX/ODS/video (needs LibreOffice/FFmpeg in the target).

## The raw RPC client

### `qrexec-client-vm` — call a qrexec service directly

```console
[user@work ~]$ qrexec-client-vm work qubes.StartApp+firefox
[user@work ~]$ qrexec-client-vm '' qubes.Filecopy < program.tar
```

- Synopsis: `qrexec-client-vm [--buffer-size=N] target service [local_program [args...]]`
- `target`: qube name, `''` (policy decides), `$dispvm`, or
  `$dispvm:template`.
- `service`: qrexec service, arguments appended after `+`
  (`some.service+arg`).
- Optional `local_program` gets its stdin/stdout piped to the remote
  service; without it, your terminal is the pipe.
- Exit codes: `126` = dom0 policy denied, `125` = invocation failed,
  otherwise the service's (or local program's) exit status.
- This is the building block every domU tool above is made of. Prefer the
  dedicated tools when one exists; drop to this when scripting a custom
  service. See [qrexec.md](qrexec.md) for the policy side.
