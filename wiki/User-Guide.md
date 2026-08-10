# User Guide

Run ArrSuite commands inside the LXC as `root`.

## Inspect applications

```bash
arrsuite list
arrsuite status
arrsuite status sonarr radarr
arrsuite version
```

## Add applications

```bash
arrsuite add
arrsuite add lidarr
arrsuite add prowlarr bazarr cleanuparr
```

Running `arrsuite add` without an application opens a checklist. Byparr and
FlareSolverr are mutually exclusive and cannot be installed together.

Sonarr and Radarr are selected by default. Lidarr, Prowlarr, Byparr,
FlareSolverr, Seerr, Bazarr, and Cleanuparr are optional and unchecked.

## Update and restart

```bash
update
arrsuite update
arrsuite update sonarr radarr
arrsuite self-update
arrsuite restart
arrsuite restart sonarr
```

`update` first attempts an ArrSuite self-update and then updates every installed
application. A self-update network failure does not prevent application
updates.

Each release includes checksummed upgrade compatibility metadata. Before any
runtime file is replaced, `arrsuite self-update` verifies that metadata,
compares the installed and target versions, and refuses downgrades. When a
direct jump is unsafe, it exits without changing the runtime and prints two
ready-to-run commands: version-pinned updates to the required bridge release,
then an update that explicitly restores `releases/latest/download`. Follow
those commands in the order shown. The explicit final URL is important because
older managers persist the pinned bridge URL in `/opt/arrsuite/update.url`.
If v1.0.31 reports that it is current when a newer release exists, run:

```bash
ARRSUITE_UPDATE_BASE_URL="https://github.com/donselkirk/arrsuite/releases/latest/download" arrsuite self-update
```

The standard `update` command reports the blocked self-update and
continues updating installed applications.

Updates for Sonarr, Radarr, Lidarr, Prowlarr, Seerr, and Bazarr first create a
backup under `/opt/arrsuite/backups/pre-update/<app>/`. Cleanuparr archives its
configuration under the same hierarchy. If a required backup fails, that
application is not updated.

## Remove or reset

```bash
# Preserve settings and databases
arrsuite remove bazarr

# Delete program files and application data
arrsuite remove bazarr --purge

# Purge and reinstall a clean copy
arrsuite reset bazarr
```

Remove and reset require confirmation. Add `--yes` for deliberate
noninteractive use. Purge and reset do not create backups.

## Installed-app registry

Successfully installed applications are tracked in:

```text
/opt/arrsuite/installed.apps
```

The login banner reads this file dynamically and shows each installed
application's URL, port, and systemd state.
