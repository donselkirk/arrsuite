# ArrSuite Community Script

ArrSuite creates a single unprivileged Debian 13 Proxmox LXC for running
multiple Arr applications directly, without Docker. Choose the applications
you want during installation, then add, update, restart, back up, or restore
them later with the `arrsuite` command.

## Built on Community Scripts

ArrSuite depends on the excellent work of the
[Proxmox VE Community Scripts](https://community-scripts.org/) project. Its
container-creation helpers, installer conventions, update tooling, and
individual application scripts provide the foundation that makes this project
possible.

ArrSuite combines several of those application patterns into one modular LXC
and adds multi-application selection and management. It is not a replacement
for Community Scripts. Please visit their website for the official script
catalog, documentation, project support, and ways to contribute to their
amazing community-maintained work.

## Supported applications

| Application | Port | Initial selection | Architecture |
|---|---:|---|---|
| Sonarr | 8989 | Selected | amd64, arm64 |
| Radarr | 7878 | Selected | amd64, arm64 |
| Lidarr | 8686 | Optional | amd64, arm64 |
| Prowlarr | 9696 | Optional | amd64 only |
| Byparr | 8191 | Optional | amd64 only |
| FlareSolverr | 8192 | Optional | amd64 only |
| Seerr | 5055 | Optional | amd64, arm64 |
| Bazarr | 6767 | Optional | amd64, arm64 |

FlareSolverr uses port 8192 in ArrSuite because its usual port conflicts with
Byparr. Sonarr and Radarr are selected by default; every other application is
unchecked. LXC nesting is disabled by default because the applications run
directly inside the container.

## Quick start

Run this command as `root` in the Proxmox VE host shell:

```bash
bash -c "$(curl -fsSL https://github.com/donselkirk/arrsuite/releases/latest/download/arrsuite.sh)"
```

The installer opens a checklist for application selection and then uses the
standard Community Scripts container-creation workflow. After installation,
open an application at `http://<LXC-IP>:<port>`.

The default container resources are:

- 2 CPU cores
- 6144 MB RAM
- 16 GB disk
- Debian 13 in an unprivileged LXC
- Nesting disabled

These defaults suit a typical multi-application installation. A container
running all applications, a large library, or browser-based services may
benefit from 8 GB RAM and 24–32 GB of disk. Mount media and download storage
separately from the LXC root disk.

## Everyday commands

Run these commands inside the ArrSuite LXC.

### View applications

```bash
# Supported applications, ports, installation state, and service state
arrsuite list

# Detailed systemd status for installed applications
arrsuite status

# Installed ArrSuite release
arrsuite version
```

The login banner also reads `/opt/arrsuite/installed.apps` dynamically and
shows each installed application's URL, port, and current service state.

### Add applications

```bash
# Open a checklist containing applications that are not installed
arrsuite add

# Add one or more applications directly
arrsuite add lidarr
arrsuite add prowlarr bazarr
```

Canceling the checklist makes no changes. An application is added to
`/opt/arrsuite/installed.apps` only after it installs successfully.

### Update applications

```bash
# Refresh ArrSuite and update every installed application
update

# Equivalent manager command
arrsuite update

# Update selected applications only
arrsuite update sonarr radarr

# Update only the ArrSuite manager and supporting tools
arrsuite self-update
```

Self-update always reports the installed release or the release it updated to.
Application data is preserved during updates. If one application update fails,
ArrSuite continues with the remaining applications and returns a failure when
the run is complete.

### Restart applications

```bash
# Restart every installed application
arrsuite restart

# Restart one or more applications
arrsuite restart sonarr
arrsuite restart sonarr radarr
```

## Backup and restore

ArrSuite currently supports application-level backup and restore for Sonarr,
Radarr, Lidarr, and Seerr.

| Application | Backup method | Includes |
|---|---|---|
| Sonarr | Native application API | Configuration and database |
| Radarr | Native application API | Configuration and database |
| Lidarr | Native application API | Configuration and database |
| Seerr | Consistent archive while stopped | Settings and SQLite database |

Backups do not include media files. By default, archives are written below
`/opt/arrsuite/backups/<app>/`.

```bash
# Back up every installed application that supports backups
arrsuite backup

# Back up selected applications
arrsuite backup sonarr radarr
arrsuite backup lidarr
arrsuite backup seerr

# Use another directory or mounted backup location
arrsuite backup radarr --output /mnt/backups
```

Restore one application from a ZIP archive:

```bash
arrsuite restore sonarr /root/sonarr_backup.zip
arrsuite restore radarr /root/radarr_backup.zip
arrsuite restore lidarr /root/lidarr_backup.zip
arrsuite restore seerr /root/arrsuite_seerr_backup.zip
```

Before restoring, ArrSuite creates a safety backup in
`/opt/arrsuite/backups/pre-restore/<app>/`. Sonarr, Radarr, and Lidarr use their
native restore endpoints. Seerr validates and safely extracts its archive,
with automatic rollback if its service does not restart.

To copy and restore a backup from the Proxmox host:

```bash
pct push <CTID> ./sonarr_backup.zip /root/sonarr_backup.zip
pct exec <CTID> -- arrsuite restore sonarr /root/sonarr_backup.zip
```

### Migrate Seerr from another installation

For a native Community Scripts Seerr LXC, run the following as `root` inside
that LXC. The final argument is the backup output directory:

```bash
bash -c "$(curl -fsSL https://github.com/donselkirk/arrsuite/releases/latest/download/seerr-backup.sh)" -- /root
```

For Docker, run the tool on the Docker host and provide the container name:

```bash
bash -c "$(curl -fsSL https://github.com/donselkirk/arrsuite/releases/latest/download/seerr-backup.sh)" -- --docker seerr /root
```

Replace `seerr` with the actual container name. Docker mode requires the
container to be running. It stops the container, copies `/app/config` while the
database is idle, skips nonportable symbolic links, creates a compatible ZIP,
and restarts the container. For a different internal config path:

```bash
SEERR_DOCKER_CONFIG_PATH=/custom/config \
  bash -c "$(curl -fsSL https://github.com/donselkirk/arrsuite/releases/latest/download/seerr-backup.sh)" -- --docker seerr /root
```

Transfer the generated ZIP to the ArrSuite LXC and run
`arrsuite restore seerr <backup.zip>`.

## Console access

If the root password is left blank during creation, ArrSuite configures root
auto-login for both Proxmox console paths:

| Service | Console |
|---|---|
| `container-getty@1.service` | Proxmox web UI (`/dev/tty1`) |
| `console-getty.service` | `pct console` (`/dev/console`) |

The installer preserves Debian's `ImportCredential=` directives while clearing
the inherited credential imports that otherwise cause `243/CREDENTIALS` in an
unprivileged Debian 13 LXC.

If an existing container has a blank console, enter it from the Proxmox host
with `pct enter <CTID>`, then run:

```bash
curl -fsSL https://github.com/donselkirk/arrsuite/releases/latest/download/fix-console-autologin.sh | bash
```

## How ArrSuite works

ArrSuite retains the Community Scripts container and installer conventions:

1. `ct/arrsuite.sh` creates the LXC and provides `/usr/bin/update`.
2. `install/arrsuite-install.sh` performs shared setup and installs the selected modules.
3. `/usr/local/bin/arrsuite` manages applications after installation.
4. `/opt/arrsuite/installed.apps` records successfully installed applications.
5. `/opt/arrsuite/lib/` stores the helper snapshots used by the manager.
6. Installs and self-updates consume validated assets from the latest GitHub release.

Each application remains an isolated module with its own dependencies, release
logic, service, data path, architecture rules, install function, and update
function. The modules follow the corresponding individual Community Scripts
implementations and reuse their helpers wherever practical.

Common paths are:

| Application | Program path | Data path | Service |
|---|---|---|---|
| Sonarr | `/opt/Sonarr` | `/var/lib/sonarr` | `sonarr.service` |
| Radarr | `/opt/Radarr` | `/var/lib/radarr` | `radarr.service` |
| Lidarr | `/opt/Lidarr` | `/var/lib/lidarr` | `lidarr.service` |
| Prowlarr | `/opt/Prowlarr` | `/var/lib/prowlarr` | `prowlarr.service` |
| Byparr | `/opt/Byparr` | — | `byparr.service` |
| FlareSolverr | `/opt/flaresolverr` | — | `flaresolverr.service` |
| Seerr | `/opt/seerr` | `/opt/seerr/config` | `seerr.service` |
| Bazarr | `/opt/bazarr` | `/var/lib/bazarr` | `bazarr.service` |

## Development

The upstream-compatible project files are:

```text
ct/arrsuite.sh
install/arrsuite-install.sh
json/arrsuite.json
```

Standalone copies of the embedded manager and login banner live in `tools/`.
Run the complete local validation suite after every change:

```bash
bash tests/static-checks.sh
git diff --check
```

The suite checks Bash syntax, JSON metadata, embedded artifact synchronization,
manager behavior, and ShellCheck when available.

Pushes to `main` that change runtime scripts run automated validation and, when
successful, publish the next GitHub release with generated notes, checksums,
and installation assets. Documentation-only changes do not create releases.
Production installs and self-updates always use the latest successful release.

Local checks cannot prove LXC creation, systemd behavior, release downloads, or
web-interface availability. Test release-affecting changes on a disposable
Proxmox node before submitting upstream.

### Proxmox test matrix

| Case | Selection or action | Expected result |
|---|---|---|
| Fresh amd64 | Sonarr + Radarr | Both services active and both web interfaces answer |
| Fresh amd64 | All applications | All services active and all configured ports answer |
| Add later | Install Sonarr, then add Radarr | Sonarr data remains and Radarr is registered |
| Update all | Run `update` with several apps | Runtime and every app are checked; later apps run after a failure |
| No update | Run `update` twice | Current releases are reported without replacing data |
| ARM64 | Sonarr + Radarr + Lidarr + Seerr + Bazarr | All install; amd64-only apps show clear architecture errors |
| Reboot | Reboot the LXC | Every installed service returns active |
| Blank password | Use both console types | Both consoles auto-login as root |
| Restore | Restore each supported app | A safety backup remains and the restored service is active |
| LXC backup | Back up and restore the container | App data and the installed-app registry remain intact |

### Remaining work before an upstream PR

- Confirm that maintainers accept an aggregate script with multiple web ports
  and a `null` metadata `interface_port`.
- Confirm the preferred aggregate name and icon.
- Confirm that persisting the Community Scripts helper bundle is acceptable.
- Decide whether container-level arm64 support should remain when some optional
  modules are amd64-only.
- Test current release asset patterns and all supported modules on Proxmox.
- Consider displaying a snapshot reminder before multi-application updates.

### Adding another application

When adding a module, update every user-facing and runtime surface: supported
application arrays, labels, descriptions, ports, checklist, help output, login
banner, completion output, JSON metadata, README, and tests. Add isolated
install and update functions, service handling, dispatch cases, dependencies,
data paths, release matching, and architecture behavior based on the current
individual Community Script.
