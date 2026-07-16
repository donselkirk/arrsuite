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
arrsuite add prowlarr bazarr
```

Running `arrsuite add` without an application opens a checklist. Byparr and
FlareSolverr are mutually exclusive and cannot be installed together.

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
