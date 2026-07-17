# ArrSuite Community Script

ArrSuite creates one Proxmox LXC that runs multiple Arr applications directly,
without Docker. Applications can be selected during installation and managed
later through one `arrsuite` command.

ArrSuite is built on the excellent work of
[Proxmox VE Community Scripts](https://community-scripts.org/), reusing its LXC
workflow, helpers, conventions, and individual application implementations
wherever practical.

## Supported applications

| Application | Port | Default |
|---|---:|---|
| Sonarr | 8989 | Selected |
| Radarr | 7878 | Selected |
| Lidarr | 8686 | Optional |
| Prowlarr | 9696 | Optional |
| Byparr | 8191 | Optional |
| FlareSolverr | 8192 | Optional |
| Seerr | 5055 | Optional |
| Bazarr | 6767 | Optional |

Byparr and FlareSolverr are mutually exclusive. Sonarr and Radarr are selected
by default; every other application is unchecked. LXC nesting is disabled by
default.

## Install

Run as `root` in the Proxmox VE host shell:

```bash
bash -c "$(curl -fsSL https://github.com/donselkirk/arrsuite/releases/latest/download/arrsuite.sh)"
```

Default resources are 2 CPU cores, 6144 MB RAM, and a 16 GB disk. Mount media
and download storage separately from the LXC root disk.

To install a specific release:

```bash
export ARRSUITE_RELEASE_BASE_URL="https://github.com/donselkirk/arrsuite/releases/download/<version>"
bash -c "$(curl -fsSL "${ARRSUITE_RELEASE_BASE_URL}/arrsuite.sh")"
```

## Common commands

Run these inside the ArrSuite LXC:

```bash
arrsuite list
arrsuite status [app ...]
arrsuite add [app ...]
arrsuite update [app ...]
arrsuite restart [app ...]
arrsuite backup [app ...]
arrsuite restore app backup.zip
arrsuite remove app
arrsuite remove app --purge
arrsuite reset app
arrsuite self-update
arrsuite version
```

The standard `update` command self-updates ArrSuite and then updates every
installed application. Remove and reset require confirmation; add `--yes` for
deliberate noninteractive use. Restore does not create an automatic backup.

## Documentation

- [User guide](https://github.com/donselkirk/arrsuite/wiki/User-Guide)
- [Backup, restore, and migration](https://github.com/donselkirk/arrsuite/wiki/Backup-and-Restore)
- [Console access and troubleshooting](https://github.com/donselkirk/arrsuite/wiki/Console-and-Troubleshooting)
- [Architecture and file layout](https://github.com/donselkirk/arrsuite/wiki/Architecture)
- [Building and development](https://github.com/donselkirk/arrsuite/wiki/Building-and-Development)
- [Integrating Community Scripts changes](https://github.com/donselkirk/arrsuite/wiki/Upstream-Integration)

## Important notes

- Installed applications are tracked in `/opt/arrsuite/installed.apps`.
- The login banner displays installed applications, ports, URLs, and service
  state.
- Blank-password console auto-login supports both the Proxmox web console and
  `pct console`.
- Local static checks do not replace testing on a disposable Proxmox node.
- ArrSuite is an independent, AI-assisted community project and is not an
  official Community Scripts release.

## Contributing

Issues, testing feedback, and contributions are welcome. Development changes
should follow [AGENTS.md](AGENTS.md) and the
[building guide](https://github.com/donselkirk/arrsuite/wiki/Building-and-Development).
