# ArrSuite Community Script — v1.2

This prototype creates one Debian LXC and lets the user choose which supported Arr applications to install. The current version supports:

- Sonarr — port 8989
- Radarr — port 7878
- Lidarr — port 8686 (optional)
- Prowlarr — port 9696 (optional; amd64 only)
- Byparr — port 8191 (optional; amd64 only)
- FlareSolverr — port 8192 (optional; amd64 only)

The implementation is intentionally bare-metal inside the LXC. It does not install Docker.

Sonarr and Radarr are selected by default. Lidarr, Prowlarr, Byparr, and
FlareSolverr are optional and unchecked in the installation checklist.
FlareSolverr uses port 8192 in ArrSuite because its upstream default of 8191
conflicts with Byparr.

## Run from a Proxmox shell

Run the repository bootstrap as root on the Proxmox VE host:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/donselkirk/arrsuite/main/arrsuite.sh)"
```

The bootstrap downloads the current Community Scripts `build.func` at runtime
and redirects only the application-specific installer request to this
repository. This keeps the container creation workflow on the latest upstream
helpers without requiring a full fork of the Community Scripts repository.

## Included upstream files

```text
ct/arrsuite.sh
install/arrsuite-install.sh
json/arrsuite.json
```

The `tests/` directory and this README are development aids and do not necessarily need to be included in the final upstream pull request.

## User commands inside the LXC

```bash
# Open a checklist containing apps that are not installed yet
arrsuite add

# Esc or Cancel closes the checklist without changing installed applications

# Add one or more named apps without the checklist
arrsuite add sonarr radarr
arrsuite add lidarr
arrsuite add prowlarr
arrsuite add byparr
arrsuite add flaresolverr

# Update every installed app
update

# Equivalent direct manager command
arrsuite update

# Update only the ArrSuite manager, banner, repair tool, and helper snapshots
arrsuite self-update

# Update only selected installed apps
arrsuite update sonarr radarr
arrsuite update lidarr

# Show supported apps, ports, installation state, and service state
arrsuite list

# Show systemd status for installed apps
arrsuite status
```

## Upgrade an existing ArrSuite LXC to v1.2

The package includes the updated manager as `tools/arrsuite-manager`. To add Lidarr to a container created by v1.1, copy the manager to the Proxmox host and run:

```bash
pct push <CTID> arrsuite-manager /usr/local/bin/arrsuite
pct exec <CTID> -- chmod 0755 /usr/local/bin/arrsuite
pct exec <CTID> -- arrsuite add lidarr
```

This replaces only the ArrSuite manager. It does not alter existing Sonarr, Radarr, or Byparr data. Lidarr then installs into its normal paths and joins the shared `update` command.

## Console auto-login

When the root password is left blank during LXC creation, the installer explicitly configures both console paths used by Proxmox:

```text
container-getty@1.service   Proxmox web console (/dev/tty1)
console-getty.service       pct console / serial console (/dev/console)
```

ArrSuite reapplies and restarts both getty configurations after the shared
Community Scripts customization step. This ensures a usable console even when
the upstream helper does not activate the template's getty service. The
drop-ins also clear Debian 13's inherited `ImportCredential` directives, which
can otherwise fail with `243/CREDENTIALS` in an unprivileged LXC.

For a container created with an earlier prototype, run the included repair script as root inside the LXC:

```bash
bash tools/fix-console-autologin.sh
```

From the Proxmox host, `pct enter <CTID>` can be used to enter an existing container without relying on its console login.

## Login banner

ArrSuite replaces the duplicate static and dynamic Community Scripts banners
with one dynamic login banner. It reads `/opt/arrsuite/installed.apps` whenever
a shell starts and shows every registered application, its URL and port, and
its current systemd state. Applications added with `arrsuite add` therefore
appear on the next login automatically; removing an application from the
registry removes it from the next banner.

To apply the banner to an existing ArrSuite container, run inside the LXC:

```bash
curl -fsSL https://raw.githubusercontent.com/donselkirk/arrsuite/main/tools/arrsuite-motd.sh \
  -o /etc/profile.d/00_lxc-details.sh
chmod 0755 /etc/profile.d/00_lxc-details.sh
: >/etc/motd
```

## Design

The standard Community Scripts container and installer structure is retained:

1. `ct/arrsuite.sh` creates the LXC and exposes the normal `/usr/bin/update` workflow.
2. `install/arrsuite-install.sh` performs shared container setup once.
3. The installer saves the Community Scripts function bundle at `/opt/arrsuite/lib/community-functions.sh`.
4. `/usr/local/bin/arrsuite` sources that bundle when adding or updating an app.
5. `/opt/arrsuite/installed.apps` is the small registry used to decide which apps participate in `update`.

The Sonarr, Radarr, Lidarr, Prowlarr, Byparr, and FlareSolverr modules closely
follow their existing Community Scripts implementations. In particular, they reuse:

- `fetch_and_deploy_gh_release`
- `check_for_gh_release`
- `arch_resolve`
- `setup_uv`
- the existing package lists, application paths, data paths, and systemd units

Each application keeps its normal paths, so troubleshooting information from the individual Community Scripts remains useful:

```text
/opt/Sonarr       /var/lib/sonarr       sonarr.service
/opt/Radarr       /var/lib/radarr       radarr.service
/opt/Lidarr       /var/lib/lidarr       lidarr.service
/opt/Prowlarr     /var/lib/prowlarr     prowlarr.service
/opt/Byparr                              byparr.service
/opt/flaresolverr                        flaresolverr.service
```

## Resource defaults

The aggregate defaults are deliberately higher than the individual scripts:

- 2 CPU cores
- 6144 MB RAM
- 16 GB disk
- Debian 13
- unprivileged LXC
- nesting disabled (the applications run directly in the LXC without Docker)

Users installing only Sonarr and Radarr can reduce the resources in Advanced
Settings. For all six applications, especially with Byparr, FlareSolverr, or large libraries,
8 GB RAM and 24–32 GB disk is a more comfortable allocation. Media and download
storage should be mounted separately from the LXC root disk.

## Local checks

From the root of this package:

```bash
bash tests/static-checks.sh
```

This checks the outer scripts, extracts and checks the embedded `arrsuite` manager, validates the JSON metadata, and runs ShellCheck when it is installed.

A real acceptance test still requires Proxmox because syntax checks cannot validate LXC creation, systemd startup, release asset matching, or application web interfaces.

## Proxmox test matrix

Before submitting upstream, test at least these cases on a disposable Proxmox node:

| Case | Selection | Expected result |
|---|---|---|
| Fresh amd64 | Sonarr + Radarr | Both services active; ports 8989 and 7878 answer |
| Fresh amd64 | All six | All services active; ports 8989, 7878, 8686, 9696, 8191, and 8192 answer |
| Add later | Initially Sonarr, then `arrsuite add radarr` | Existing Sonarr data remains; Radarr is added |
| Update all | Run `update` after installing all four | Every registered app is checked; one failure does not prevent later apps being attempted |
| No update | Run `update` twice | Second run reports current releases without replacing data |
| ARM64 | Sonarr + Radarr + Lidarr | All three install; Prowlarr, Byparr, and FlareSolverr selections fail with clear architecture messages |
| Reboot | Reboot the LXC | Every installed service returns active |
| Blank password | Leave root password blank | Web console and `pct console` auto-login as root |
| Backup restore | Back up and restore the LXC | App configurations and registry remain intact |

## Testing from a fork

New scripts currently belong in the `community-scripts/ProxmoxVED` development repository. Create a feature branch in your fork, copy the three upstream files into their matching directories, and adjust the `build.func` source in `ct/arrsuite.sh` to your fork/branch while testing. Run the CT script from the Proxmox host.

Suggested branch name:

```text
feat/add-arrsuite
```

Suggested commit:

```text
feat: add selectable multi-app ArrSuite container
```

## Items to resolve before an upstream PR

1. Ask maintainers whether an aggregate script with several web ports is acceptable under one metadata entry. `interface_port` is currently `null` for that reason.
2. Confirm the preferred aggregate name and icon. The metadata currently uses `ArrSuite` and a proposed Servarr icon URL.
3. Confirm whether persisting the installer’s Community Scripts function bundle is acceptable. It avoids custom GitHub logic and enables future app additions, but maintainers may prefer a project-provided runtime library or a refresh command.
4. Decide whether ARM64 should remain enabled for the container even though Prowlarr, Byparr, and FlareSolverr are amd64-only in their current Community Scripts.
5. Test the current Sonarr, Radarr, and Lidarr release asset patterns against both amd64 and arm64.
6. Consider a snapshot warning before updating several applications in one operation.

## Adding another application module

A future module should add these pieces to the embedded manager:

1. Add its lowercase name to `SUPPORTED_APPS`.
2. Add label, description, and port entries.
3. Add `install_<app>` using the existing Community installer as the source of truth.
4. Add `update_<app>` using the existing Community CT update function as the source of truth.
5. Add the application to the two `case` statements.
6. Test install, add-later, update, reboot, and failure behavior.

Keeping each module close to the corresponding upstream script is more maintainable than inventing one generic installer for applications that only appear similar.
