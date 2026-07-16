# ArrSuite Development Instructions

## Project purpose

ArrSuite creates one unprivileged Debian 13 Proxmox LXC that runs multiple
Arr applications directly, without Docker. Preserve the Community Scripts
workflow and conventions wherever practical.

Supported applications and ports:

- Sonarr: 8989
- Radarr: 7878
- Lidarr: 8686
- Prowlarr: 9696 (amd64 only)
- Byparr: 8191 (amd64 only)
- FlareSolverr: 8192 (amd64 only; changed from upstream 8191 to avoid Byparr)
- Seerr: 5055
- Bazarr: 6767

Sonarr and Radarr must be selected by default. All other applications must be
optional and unchecked. LXC nesting must default to disabled.

## Required behavior

- Allow initial application selection through the installer checklist.
- Byparr and FlareSolverr are mutually exclusive. Never offer or install one
  while the other is installed, and reject a request that selects both.
- Support `arrsuite add [app ...]`, `arrsuite list`, `arrsuite status [app ...]`, and
  `arrsuite update [app ...]`, `arrsuite restart [app ...]`, plus
  `arrsuite self-update`.
- Support confirmed `arrsuite remove` and `arrsuite reset` operations. Removal
  preserves application data unless `--purge` is specified. Reset purges data
  and reinstalls the application. Purge and reset do not create backups;
  `--yes` permits deliberate noninteractive operation.
- Unknown commands must return a concise error naming the command, display
  usage, and exit nonzero without invoking the inherited global error trap.
- App-targeted update, restart, status, backup, and restore operations must
  validate that the app is supported and installed before acting. Missing apps
  must fail cleanly and show `arrsuite add <app>` when installation is possible.
- Expected CLI validation failures must not emit stack-style `in line ...`
  diagnostics. Clear the inherited `ERR` trap before `main`, but retain
  `errexit`; do not invoke `main` in an OR-list because Bash would disable
  `errexit` throughout nested manager functions.
- Prebuilt application updates must stage and validate the new release before
  stopping the service. Keep the previous program directory until the updated
  service is active, and restore it when deployment or startup fails.
- Self-update must verify downloaded runtime assets against the release's
  `SHA256SUMS` before installing them.
- `/usr/bin/update` must attempt an ArrSuite self-update and then update every
  installed application. A self-update network failure must not prevent
  application updates.
- Support Sonarr, Radarr, Lidarr, Prowlarr, Seerr, and Bazarr backup creation and restoration through
  `arrsuite backup` and `arrsuite restore`; restores must not create an automatic
  pre-restore backup. Sonarr, Radarr, Lidarr, and Prowlarr use native APIs.
  Seerr and Bazarr use validated archives of `/opt/seerr/config` and
  `/var/lib/bazarr`, respectively, while their services are stopped.
- Track installed applications in `/opt/arrsuite/installed.apps`.
- A failed install must never be added to the registry.
- Continue processing remaining applications if one update fails, then return
  a failure result.
- Keep each application's install, update, service, dependencies, release
  asset, data path, and architecture behavior isolated from other modules.
- Base application behavior on the current individual Community Scripts
  implementation in `community-scripts/ProxmoxVED`; consult the previous
  `community-scripts/ProxmoxVE` repository only when a script has been removed
  from the development repository.

## Files that must remain synchronized

- `apps/*.sh` contains the editable application service, install, dependency,
  update, release, data-path, and architecture modules.
- `templates/systemd/*.service` and `templates/config/*` contain service and
  application configuration payloads referenced by the modules.
- `templates/getty/*` and `templates/update.sh` contain installer-created
  runtime files.
- `src/arrsuite-install.sh.in` is the editable installer structure.
- `src/arrsuite-manager.sh.in` contains the shared manager implementation.
- `tools/build-artifacts.sh` generates `tools/arrsuite-manager` and embeds it in
  `install/arrsuite-install.sh`. Do not edit either generated artifact directly;
  run the builder after changing a module, source file, or template.
- `tools/arrsuite-motd.sh` is the standalone copy of the login banner embedded
  in `install/arrsuite-install.sh`.
- `wiki/*.md` contains the source for detailed GitHub Wiki documentation. Keep
  the README concise and user-focused; put development, architecture,
  troubleshooting, backup, and upstream-integration detail in the Wiki.
  `.github/workflows/wiki.yml` publishes these canonical sources to the GitHub
  Wiki whenever they change on `main`; do not maintain Wiki pages separately.
- `tests/static-checks.sh` verifies the generated manager and both embedded
  artifacts byte-for-byte. Regenerate whenever a source artifact changes.

`tools/upstream-lock.json` records the exact Community Scripts install and CT
source blobs reviewed for every application. Run `bash tools/check-upstream.sh`
to detect changes and generate focused diffs under `upstream-report/`. Review
the diffs and update the relevant `apps/<app>.sh`; never execute new upstream
content automatically. Update the lock only after the imported behavior has
been reviewed and tested.

When adding an application, update all relevant surfaces:

- supported-app array, label, description, and port maps;
- service writer, install function, update function, and dispatch cases;
- initial checklist default state and help output;
- login-banner port mapping;
- CT completion output, JSON metadata, README, and tests.

## Console requirements

When the LXC root password is blank, auto-login must work through both:

- `container-getty@1.service` for the Proxmox web UI `/dev/tty1` console;
- `console-getty.service` for `/dev/console` and `pct console`.

Do not remove `ImportCredential=` from the getty drop-ins. Debian 13's inherited
credential imports fail with `243/CREDENTIALS` in an unprivileged LXC. The
installer must unmask, enable, reset failures for, and restart both services.

The login banner must display only once. It must dynamically read
`/opt/arrsuite/installed.apps` and show each installed application's URL, port,
and current systemd state.

## Bootstrap constraints

`arrsuite.sh` must continue using the current official Community Scripts
helpers while redirecting only the application-installer URL to this
repository's latest GitHub release. Fresh installs, `update`, and
`self-update` must default to `releases/latest/download`; a raw commit URL may
remain available only as an explicit development override. Do not enable Bash
`nounset` in the bootstrap; explicitly retain `set +u` because upstream helpers
reference optional unset variables such as `SSH_CLIENT`.

Do not run a Community Scripts `msg_info` spinner behind a `whiptail` dialog.

## Verification

Run after every change:

```bash
bash tools/build-artifacts.sh
bash tests/static-checks.sh
```

This must cover Bash syntax, JSON parsing, embedded artifact synchronization,
manager behavior, and ShellCheck when available. For release-affecting changes,
also run `git diff --check`. A real upstream submission still requires testing
on a disposable Proxmox node; local static tests do not prove LXC creation,
systemd startup, release downloads, or web interfaces.

## Commit and handoff workflow

- Commit completed changes to `main` and push to
  `https://github.com/donselkirk/arrsuite.git` when the user asks for a change.
- Use focused commit messages such as `feat: add Prowlarr module` or
  `fix: clear getty credentials in unprivileged LXC`.
- Every push to `main` must run GitHub Actions validation and create the next
  patch release with generated change notes and stable runtime assets.
- After every pushed change, verify the generated release and provide a
  cache-bypassing, version-pinned installation command using that release:

```bash
ARRSUITE_RELEASE_BASE_URL="https://github.com/donselkirk/arrsuite/releases/download/<version>" \
bash -c "$(curl -fsSL https://github.com/donselkirk/arrsuite/releases/download/<version>/arrsuite.sh)"
```

- When applicable, also provide commit-pinned commands to update or repair an
  existing LXC without reinstalling it.
