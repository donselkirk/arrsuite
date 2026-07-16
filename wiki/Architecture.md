# Architecture

ArrSuite retains the Community Scripts container and installer workflow while
adding modular multi-application management.

## Runtime

1. `arrsuite.sh` loads the current Community Scripts build framework.
2. `ct/arrsuite.sh` creates the LXC.
3. `install/arrsuite-install.sh` installs selected applications.
4. `/usr/local/bin/arrsuite` manages applications afterward.
5. `/opt/arrsuite/installed.apps` records successful installations.
6. `/usr/bin/update` self-updates ArrSuite and updates installed applications.

Production installs and self-updates use stable assets from the latest GitHub
release. A raw repository URL is available only as an explicit development
override.

## Source and generated files

```text
apps/                         Application install and update modules
src/arrsuite-manager.sh.in    Shared manager source
src/arrsuite-install.sh.in    Installer structure
templates/systemd/            Systemd unit sources
templates/getty/              Console override sources
templates/config/             Application configuration payloads
templates/update.sh           Standard update wrapper
tools/arrsuite-motd.sh        Login banner source

tools/arrsuite-manager        Generated manager
install/arrsuite-install.sh   Generated self-contained installer
```

The generated installer remains one file for reliable Community Scripts-style
deployment. Editable components remain separated for review and testing.

## Application paths

| Application | Program | Data | Service |
|---|---|---|---|
| Sonarr | `/opt/Sonarr` | `/var/lib/sonarr` | `sonarr.service` |
| Radarr | `/opt/Radarr` | `/var/lib/radarr` | `radarr.service` |
| Lidarr | `/opt/Lidarr` | `/var/lib/lidarr` | `lidarr.service` |
| Prowlarr | `/opt/Prowlarr` | `/var/lib/prowlarr` | `prowlarr.service` |
| Byparr | `/opt/Byparr` | — | `byparr.service` |
| FlareSolverr | `/opt/flaresolverr` | — | `flaresolverr.service` |
| Seerr | `/opt/seerr` | `/opt/seerr/config` | `seerr.service` |
| Bazarr | `/opt/bazarr` | `/var/lib/bazarr` | `bazarr.service` |
