# ArrSuite AI Specification

This is the canonical product and reconstruction contract for ArrSuite. An
implementation agent reads this file and `AGENTS.md` before changing code.
Exact upstream helper contents and generated payloads remain in the repository;
this file defines behavior, boundaries, and invariants.

## 1. Product and platform

ArrSuite creates one unprivileged Debian 13 Proxmox LXC running selected Arr
applications directly, without Docker. It preserves the Community Scripts
workflow while adding one shared manager, backup boundary, update process, and
login experience. The container is a shared failure domain, although each app
must remain isolated in code, service, dependencies, data, release assets, and
architecture handling.

Defaults and constraints:

- Debian 13, unprivileged LXC, nesting disabled; suggested resources are 2 CPU,
  6144 MiB RAM, and 16 GiB disk.
- Blank root password is supported; there are no default credentials.
- Sonarr and Radarr are selected by default. All other apps are optional and
  unchecked.
- Prowlarr, Byparr, and FlareSolverr are amd64-only. Sonarr, Radarr, Lidarr,
  Seerr, Bazarr, and Cleanuparr support arm64.
- Byparr and FlareSolverr are mutually exclusive and must never be installed
  together.

## 2. Application matrix

| App | Port | Program | Data/config | Service | Upstream asset |
|---|---:|---|---|---|---|
| Sonarr | 8989 | `/opt/Sonarr` | `/var/lib/sonarr` | `sonarr.service` | `Sonarr/Sonarr`, prebuilt tarball |
| Radarr | 7878 | `/opt/Radarr` | `/var/lib/radarr` | `radarr.service` | `Radarr/Radarr`, prebuilt tarball |
| Lidarr | 8686 | `/opt/Lidarr` | `/var/lib/lidarr` | `lidarr.service` | `Lidarr/Lidarr`, prebuilt tarball |
| Prowlarr | 9696 | `/opt/Prowlarr` | `/var/lib/prowlarr` | `prowlarr.service` | `Prowlarr/Prowlarr`, x64 tarball |
| Byparr | 8191 | `/opt/Byparr` | application tree | `byparr.service` | `ThePhaseless/Byparr`, source tarball + uv |
| FlareSolverr | 8192 | `/opt/flaresolverr` | application tree | `flaresolverr.service` | `FlareSolverr/FlareSolverr`, x64 archive |
| Seerr | 5055 | `/opt/seerr` | `/opt/seerr/config` | `seerr.service` | `seerr-team/seerr`, source + Node 22/pnpm |
| Bazarr | 6767 | `/opt/bazarr` | `/var/lib/bazarr` | `bazarr.service` | `morpheus65535/bazarr`, zip + Python 3.12/uv |
| Cleanuparr | 11011 | `/opt/cleanuparr` | `/etc/cleanuparr`; logs `/var/log/cleanuparr` | `cleanuparr.service` | `Cleanuparr/Cleanuparr`, architecture zip |

Each `apps/<app>.sh` owns service writing, install, update, dependencies,
release pattern, data migration, backup hooks, and architecture behavior. A
generic installer must not erase those differences.

Dependencies and special behavior:

- Sonarr/Radarr: sqlite3 and libicu-dev.
- Lidarr: sqlite3, libchromaprint-tools, libicu-dev, mediainfo.
- Prowlarr: sqlite3 and libicu-dev; dependency repair also runs before update.
- Byparr: browser/GUI libraries, fonts, ffmpeg, xvfb, uv, and invisible-
  playwright browser assets; run `uv sync --link-mode copy` and fetch browsers.
- FlareSolverr: apt-transport-https, xvfb, signed Google Chrome repository,
  Chrome installation, then remove the temporary repository.
- Seerr: build-essential, python3-setuptools, Node 22, package-manager version
  declared in package.json, frozen install, and production build.
- Bazarr: Python 3.12 via uv, remove incompatible Pillow-only-binary option,
  create the venv, install requirements and psycopg2-binary.
- Cleanuparr has no extra application dependency beyond its release asset.
- A failed install must never enter `/opt/arrsuite/installed.apps`.

## 3. Runtime architecture

The runtime flow is: `arrsuite.sh` resolves and verifies a release; `ct/arrsuite.sh`
creates the LXC; `install/arrsuite-install.sh` installs selected apps and
runtime files; `/usr/local/bin/arrsuite` manages the container; and
`/usr/bin/update` attempts self-update before updating every installed app.
Successful apps are newline-delimited in `/opt/arrsuite/installed.apps`.

Editable source boundaries:

- `apps/*.sh`: application modules.
- `src/arrsuite-manager.sh.in`: manager source.
- `src/arrsuite-install.sh.in`: installer source.
- `templates/systemd`, `templates/config`, `templates/getty`, and
  `templates/update.sh`: runtime templates.
- `tools/arrsuite-motd.sh`: banner source.
- `vendor/community-scripts/misc/*.func`: reviewed helper copies.
- `tools/upstream-lock.json`: exact upstream provenance.

`tools/build-artifacts.sh` generates `tools/arrsuite-manager` and embeds it in
`install/arrsuite-install.sh`. Never edit generated artifacts directly. They
must remain byte-for-byte synchronized and are checked by `tests/static-checks.sh`.

Persistent manager paths include `/opt/arrsuite/version`,
`/opt/arrsuite/update.url`, `/opt/arrsuite/lib`, `/opt/arrsuite/backups`, and
the manager, MOTD, and console-repair paths under `/usr/local`.

Supported development overrides include `ARRSUITE_BASE_DIR`,
`ARRSUITE_MANAGER_PATH`, `ARRSUITE_REGISTRY`, `ARRSUITE_APP_INSTALL_ROOT`,
`ARRSUITE_APP_DATA_ROOT`, `ARRSUITE_SYSTEMD_UNIT_DIR`,
`ARRSUITE_UPDATE_BASE_URL`, `ARRSUITE_HELPER_BASE_URL`,
`COMMUNITY_SCRIPTS_URL`, and `ARRSUITE_SKIP_SELF_UPDATE`. Production defaults
must remain release-pinned.

## 4. CLI contract

```text
arrsuite list
arrsuite status [app ...]
arrsuite add [app ...]
arrsuite update [app ...]
arrsuite restart [app ...]
arrsuite backup [app ...] [--output directory]
arrsuite restore app backup.zip
arrsuite remove app [--purge] [--yes]
arrsuite reset app [--yes]
arrsuite self-update
arrsuite version
update
```

`arrsuite add` without arguments opens a checklist. Sonarr/Radarr are ON by
default; all others are OFF. Unknown commands and invalid/uninstalled app
targets fail concisely, show usage or an install hint, and do not emit Bash
stack diagnostics. Updates continue through remaining apps after a failure and
return failure if any operation failed. Removal preserves data unless
`--purge`; reset purges and reinstalls. Removal/reset require confirmation
unless `--yes` is supplied. Interactive confirmation prompts must be visible on
the controlling terminal. `update` self-updates first, but a self-update network
or compatibility failure must not prevent application updates.

The banner appears once, reads the registry dynamically, and shows every
installed app's URL, port, and current systemd state.

## 5. Backup, staging, and rollback

Native API backups are required for Sonarr, Radarr, Lidarr, and Prowlarr.
Seerr and Bazarr use validated archives while stopped. Backups exclude media;
normal destinations are `/opt/arrsuite/backups/<app>/`.

Before updating Sonarr, Radarr, Lidarr, Prowlarr, Seerr, or Bazarr, create a
verified backup at `/opt/arrsuite/backups/pre-update/<app>/` and abort that app
if backup creation fails. Cleanuparr archives `/etc/cleanuparr` as a compressed
tar file in the same hierarchy. Restore never creates an automatic backup.

Prebuilt updates stage and validate the replacement before stopping a service.
Keep the old program directory until the new service is active; restore it on
deployment/startup failure. Seerr must copy, never move, the old
`/opt/seerr/config` into the staged tree and retain the old tree for rollback.
Byparr, Bazarr, and Seerr use staged home directories so tool state is retained.
Seerr/Bazarr archives validate expected paths and service startup. External
Bazarr PostgreSQL data requires separate backup; Cleanuparr safety archives are
not accepted by `arrsuite restore`.

## 6. Console and security invariants

Blank-password auto-login must work through both
`container-getty@1.service` (`/dev/tty1`, Proxmox web console) and
`console-getty.service` (`/dev/console`, `pct console`). The installer unmasks,
enables, resets failures for, and restarts both. Keep `ImportCredential=` in
drop-ins: Debian 13 inherited credential imports fail in an unprivileged LXC
with `243/CREDENTIALS`.

Keep `set +u` in bootstrap; upstream helpers reference optional variables such
as `SSH_CLIENT`. Do not enable nounset. Do not run a Community Scripts spinner
behind a whiptail dialog. Validate architecture, registry state, release
versions, checksums, downloaded scripts, and backup archives before use.

## 7. Bootstrap and self-update

Fresh install, `update`, and `self-update` default to
`https://github.com/donselkirk/arrsuite/releases/latest/download`. Resolve
`latest` to one exact release, then use that version for installer and reviewed
helper assets. Raw commits/live upstream are development overrides only.

Every release publishes `VERSION`, `COMPATIBILITY`, `SHA256SUMS`, runtime and
installer scripts, CT script, backup tool, and all reviewed helper `.func` files.
Self-update verifies every downloaded asset against `SHA256SUMS` before
replacement and refuses downgrades.

Current compatibility metadata is schema 2:

```text
schema=2
minimum_direct_version=v1.0.31
bridge_version=v1.0.31
bridge_runs=2
legacy_helper_fix_before=v1.0.29
legacy_helper_url=https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main
```

The evidence-backed direct-update baseline is v1.0.31, the first release with
the complete checksummed helper bundle. v1.0.29/v1.0.30 need two pinned
v1.0.31 passes, then an explicit latest-release pass. Earlier or unversioned
installations also set `COMMUNITY_SCRIPTS_URL` to the active ProxmoxVE URL on
the first bridge pass because those managers default to retired ProxmoxVED.
The final pass must explicitly use
`ARRSUITE_UPDATE_BASE_URL=https://github.com/donselkirk/arrsuite/releases/latest/download`:
old managers persist a pinned bridge in `/opt/arrsuite/update.url`.

Managers before compatibility metadata ignore the gate, so current assets must
preserve the legacy download protocol and perform required migrations. Never
claim broader compatibility without tagged updater code, assets, tests, and
release-note evidence.

## 8. Upstream and release automation

`tools/check-upstream.sh` is read-only comparison/reporting. The weekly
`.github/workflows/upstream-check.yml` imports only mechanically safe reviewed
helper changes, locks exact blobs, and creates a merge-ready PR. Semantic app
changes go to the official Codex GitHub Action using
`.github/codex/prompts/upstream-review.md`; it must preserve ports, data,
backups, staged rollback, architecture, mutual exclusion, and skipped-version
behavior. The detector's focused report is the authoritative input to the
network-isolated Codex step; the agent must not rerun either upstream checker,
because doing so would replace those inputs and require unavailable network
access. No agent may push `main`, merge, alter release configuration during
focused adaptation, or bypass pending-marker/allowed-path checks.

The workflow explicitly installs ShellCheck and ripgrep because hosted images
change independently. It uploads focused reports. Any upstream or release
failure creates or refreshes one assigned `needs-local-codex` issue containing
run URL, stage outcomes, artifacts, and repair instructions; recovered issues
close automatically.

Protected `main` accepts only manually approved squash merges. PR validation is
read-only and never publishes releases. Each resulting main push validates,
creates or verifies one patch release with generated Important Changes and
comparison notes, publishes stable checksummed assets, verifies the payload,
and publishes Wiki sources. No workflow may auto-merge.

## 9. Rebuild and acceptance sequence

1. Create the Debian 13 unprivileged CT wrapper, resource metadata, and reviewed
   Community Scripts bootstrap.
2. Implement release resolution/checksum-pinned helpers and the installer.
3. Add templates, console repair, update wrapper, MOTD, registry, and manager.
4. Implement each app module and service independently, then checklist/CLI
   dispatch and mutual-exclusion/architecture validation.
5. Implement backups/restores, staged updates, rollback, compatibility metadata,
   and self-update.
6. Generate artifacts, metadata, release assets, workflows, and Wiki sources.
7. Add deterministic tests and upstream lock/provenance checks.

Acceptance requires Bash syntax, JSON, generated parity, manager behavior,
checksum assets, helper provenance, ShellCheck when available, and
`git diff --check`. A disposable Proxmox test must additionally prove CT
creation, both console paths, blank-password login, app selection, architecture
rejection, service startup, web ports, update rollback, backup/restore,
self-update, and release downloads. Local tests cannot prove LXC behavior.

## 10. Source map

- Product/agent contract: `AI_SPEC.md`, `AGENTS.md`.
- User procedures: `wiki/User-Guide.md`, `wiki/Backup-and-Restore.md`.
- Architecture: `wiki/Architecture.md`.
- Development/release: `wiki/Building-and-Development.md`.
- App behavior: `apps/*.sh`, templates, and `tools/upstream-lock.json`.
- Generated artifacts: `tools/build-artifacts.sh`, `tools/arrsuite-manager`,
  `install/arrsuite-install.sh`.
- Validation: `tests/static-checks.sh`, `tests/manager-behavior.sh`,
  `tests/bootstrap-behavior.sh`, `tests/upstream-review-behavior.sh`.
- Automation: `.github/workflows/release.yml`, `upstream-check.yml`, `wiki.yml`.
