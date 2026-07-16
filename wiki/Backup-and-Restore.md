# Backup and Restore

Backup and restore are supported for Sonarr, Radarr, Lidarr, Prowlarr, Seerr,
and Bazarr.

| Application | Method |
|---|---|
| Sonarr | Native application API |
| Radarr | Native application API |
| Lidarr | Native application API |
| Prowlarr | Native application API |
| Seerr | Validated archive while stopped |
| Bazarr | Validated archive while stopped |

Backups do not include media files.

## Create backups

```bash
arrsuite backup
arrsuite backup sonarr radarr
arrsuite backup seerr
arrsuite backup radarr --output /mnt/backups
```

The default destination is `/opt/arrsuite/backups/<app>/`.

## Restore

```bash
arrsuite restore sonarr /root/sonarr_backup.zip
arrsuite restore prowlarr /root/prowlarr_backup.zip
arrsuite restore seerr /root/arrsuite_seerr_backup.zip
arrsuite restore bazarr /root/arrsuite_bazarr_backup.zip
```

Restore does not create an automatic backup. Create one explicitly first if
you want a recovery copy. Seerr and Bazarr validate archive paths and retain
automatic rollback if the restored service cannot start.

Bazarr backup support covers ArrSuite's default SQLite configuration. An
external PostgreSQL database must be backed up separately.

## Transfer from the Proxmox host

```bash
pct push <CTID> ./sonarr_backup.zip /root/sonarr_backup.zip
pct exec <CTID> -- arrsuite restore sonarr /root/sonarr_backup.zip
```

## Migrate Seerr

From a Community Scripts Seerr LXC:

```bash
bash -c "$(curl -fsSL https://github.com/donselkirk/arrsuite/releases/latest/download/seerr-backup.sh)" -- /root
```

From a Docker host:

```bash
bash -c "$(curl -fsSL https://github.com/donselkirk/arrsuite/releases/latest/download/seerr-backup.sh)" -- --docker seerr /root
```

Docker mode stops the named container, copies `/app/config`, creates a
compatible ZIP, and restarts the container. Override the internal path with
`SEERR_DOCKER_CONFIG_PATH` when necessary.
