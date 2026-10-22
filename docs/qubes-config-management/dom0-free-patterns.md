# Applying config without a dom0 shell

Goal: change this machine's configuration from a qube, declaratively,
without an interactive dom0 session — and without making that qube
dom0-equivalent by accident. The repo's current mechanisms, for reference:

- `opt/*.sh` — imperative `qvm-*` provisioners run in dom0.
- `dom0-sync-dots.sh` / `dom0-clone-dots.sh` — dom0 pulls this repo from a
  qube with `qvm-run --pass-io … | tar -x`. **Nothing is verified**: dom0
  fully trusts that qube and the git remote.
- `qrexec/` + `opt/dom0-shell/` — `dev.Shell`, an unrestricted dom0 root
  shell over qrexec (test machines only; see
  [../qubes-shelling-into-dom0/](../qubes-shelling-into-dom0/README.md)).

## The hard boundary

The Admin API manages **qubes.xml state**: qubes, properties, features,
tags, volumes, devices, firewall, backups (execute only), template import.
It has **no call that writes an arbitrary dom0 file** or installs a dom0
package. The single exception, `policy.Replace`/`policy.include.*`, edits
`/etc/qubes/policy.d` — and the stock policy file says this "effectively
gives the caller full control over the system"
(`qubes-core-qrexec/policy.d/90-admin-policy-default.policy:8-10`).

So for this repo, which is mostly dom0 desktop config, **some dom0-side
apply step is unavoidable**. The patterns below differ in how much dom0
has to trust to run it.

## Patterns

### 1. dom0 pulls, verifies, applies
dom0 fetches from a qube via `qvm-run --pass-io`, verifies a signature
against a key pinned in dom0, then runs `qubesctl` / `install.sh`.

- Official stance: "Copying anything into dom0 is not advised"
  (`how-to-copy-from-dom0.rst:68`), yet the method itself is documented
  right after it. dom0 updates follow the same download-then-verify shape.
- Prior art: qusal's INSTALL.md — tar the repo into dom0, verify the
  maintainer key fingerprint by hand, `git verify-commit HEAD`, copy into
  `/srv/salt` + a `minion.d` drop-in. qusal itself warns that shipping
  `.git` weakens this (`.git/info/exclude` can hide modified files).
- **Verify before parsing** (our inference, not upstream guidance): pull
  two plain files — `git archive` of a signed tag and a detached
  signature — and run `gpgv --keyring <pinned>` *before* `tar` or `git`
  touches the payload. Keeps git out of dom0 entirely.
- Trust: the signing key + dom0's gpgv. Effort: low.

### 2. Config as signed RPMs
Package the config, publish a signed repo, `qubes-dom0-update` it.
SecureDrop Workstation and unman's shaker do this (shaker's `%post` runs
`qubesctl state.apply`; removing the package does *not* revert).

- Trust: dom0's RPM signature check — the same path as official updates.
- Versioning and rollback for free; arrives via the UpdateVM.
- Effort: high for one person (build, sign, host) and a rebuild per
  change. Right for fleets, overkill for dotfiles that change daily.

### 3. Admin qube on the Admin API
`qubesadmin` scripts, `qvm-*` tools or qubes-ansible ManagementVM mode
from a dedicated qube. See [ansible.md](ansible.md) and
[../qubes-admin-api/automation.md](../qubes-admin-api/automation.md).

- Covers qube lifecycle and properties, and `qvm-template` (which "works
  in both dom0 and management VMs", `template-manager.rst:50`; that qube
  then becomes your template-signature trust root).
- Cannot touch dom0 files. Needs one-time dom0 policy + packages.
- Worth it only if scoped (`created-by-` tags, read-only global, no
  `policy.*` write, no self-rwx). With global rwx + policy write it is
  dom0 with a bigger attack surface.

### 4. Configuring what's *inside* templates and qubes
- **Management disposable** (`qubesctl --skip-dom0 --targets=…` or
  qubes-ansible's proxy): declarative and idempotent, nothing installed in
  the target, dom0 never parses target output.
- **Self-configuring template** (what `opt/qubes-tpl-lolterm.sh` does with
  lolterm): dom0 `qvm-run`s a fixed bootstrap command and the template
  fetches through the updates proxy. dom0 sends but never parses — good —
  but it's imperative; wrap it in a `creates:`/`unless:` guard if moved
  into Salt.
- **`vm-config.*` features + `qubesdb-read`** to parameterise per-qube
  behaviour from dom0 or an admin qube.

### 5. Trigger: fixed service vs general shell
`developer/services/qrexec.rst:167,185` contrasts `qubes.VMShell`
(arbitrary commands, equivalent to full control) with services like
`qubes.StartApp` (fixed actions, filtered arguments). The same reasoning
applies to a dom0 service:

- `my.ApplyConfig` (hypothetical name): ignores stdin, takes at most a
  sanitised argument (e.g. a tag name), and makes **dom0** do pattern 1
  (pull from a pinned qube, verify against a pinned key, apply).
- A compromised caller can then only re-apply already-signed content —
  **provided the signing key isn't in the calling qube** (split-gpg with
  `ask`, or a hardware token). Add anti-rollback: dom0 records the last
  applied tag and refuses older ones.
- `dev.Shell` remains dom0 root for whoever can call it.
- No upstream dev statement endorses this exact design; it follows from
  the documented qrexec service guidance.

### 6. Reconciliation / events
- dom0 systemd timer running `qubesctl … test=True` to *report* drift (and
  remember #9279: `qvm.prefs` can still change things in test mode).
- Admin-qube `EventsDispatcher` reacting to `domain-add` (tag/feature
  fix-ups within its policy scope).
- No published personal-setup reconciliation loop was found.

## Layered design for this repo

| Layer | Content | Engine | Runs in |
|---|---|---|---|
| Qube topology | qubes, prefs, features, tags, devices | qubes-ansible `qube` module (or Salt `qvm.*`) | mgmt qube (or dom0) |
| Qube/template contents | packages, files, services | management disposable (Ansible proxy or `qubesctl --skip-dom0`) | `default-mgmt-dvm` |
| dom0 files | `~/.config/i3` etc., `/etc/qubes/policy.d/30-user.policy`, rpc services | `install.sh` or Salt `saltenv=user` | dom0, via verified pull |
| Trigger | "apply signed tag X" | `my.ApplyConfig` qrexec service, policy `ask` | dom0 |
| Fallback | everything | `opt/*.sh`, `dom0-*-dots.sh`, `dev.Shell` (test machine) | dom0 |

Unavoidably manual in dom0, once: pinning the signing key by fingerprint;
installing the trigger service and its policy; admin-qube policy/includes;
`qubes-ansible` packages if used; `qubes.user-dirs` if using Salt; dom0
package updates thereafter.

## Open questions

- Does `qubesctl` behave when invoked from a qrexec service as root with
  no `DISPLAY`? dom0 i3 states will likely need `runuser -u <user>`, as
  `dev.Shell` already does.
- Is `qubes-core-admin-client` present by default in the F44/Debian 13
  templates, or only via `qubes-ansible-admin`?
- Can an admin qube manage *pre-existing* qubes safely without blanket
  `created-by` tagging? Neither docs nor CI address it.
