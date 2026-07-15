#!/usr/bin/env bash
set -Eeuo pipefail

[[ $EUID -eq 0 || "${SEERR_BACKUP_ALLOW_NON_ROOT:-0}" == "1" ]] || {
  echo "Run this script as root inside the Seerr LXC." >&2
  exit 1
}

output_dir="${1:-$PWD}"
config_dir="${SEERR_CONFIG_DIR:-}"
if [[ -z "$config_dir" ]]; then
  for candidate in /opt/seerr/config /opt/jellyseerr/config /var/lib/seerr; do
    if [[ -d "$candidate" ]]; then
      config_dir="$candidate"
      break
    fi
  done
fi
[[ -d "$config_dir" ]] || {
  echo "Unable to find the Seerr config directory. Set SEERR_CONFIG_DIR explicitly." >&2
  exit 1
}
[[ -f "$config_dir/db/db.sqlite3" ]] || {
  echo "Only Seerr SQLite installations are supported; db/db.sqlite3 was not found." >&2
  exit 1
}
command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required to create the backup archive." >&2
  exit 1
}

service=""
for candidate in seerr.service jellyseerr.service; do
  if systemctl cat "$candidate" &>/dev/null; then
    service="$candidate"
    break
  fi
done
[[ -n "$service" ]] || {
  echo "Unable to find seerr.service or jellyseerr.service." >&2
  exit 1
}

install -d -m 0750 "$output_dir"
timestamp="$(date +%Y.%m.%d_%H.%M.%S)"
archive="${output_dir%/}/arrsuite_seerr_backup_${timestamp}.zip"
temp_archive="$(mktemp "${output_dir%/}/.seerr-backup.XXXXXX")"
was_active=0
systemctl is-active --quiet "$service" && was_active=1

cleanup() {
  rm -f "$temp_archive"
  if ((was_active)); then
    systemctl start "$service" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if ((was_active)); then
  printf 'Stopping %s for a consistent SQLite backup...\n' "$service"
  systemctl stop "$service"
fi

python3 - "$config_dir" "$temp_archive" <<'PYTHON'
import datetime
import json
import os
import stat
import sys
import zipfile

source, destination = sys.argv[1:]
manifest = {
    "application": "seerr",
    "format": "arrsuite-seerr-backup",
    "schema": 1,
    "created": datetime.datetime.now(datetime.timezone.utc).isoformat(),
}

with zipfile.ZipFile(destination, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    archive.writestr("arrsuite-backup.json", json.dumps(manifest, indent=2) + "\n")
    for root, directories, files in os.walk(source):
        for name in list(directories) + files:
            path = os.path.join(root, name)
            mode = os.lstat(path).st_mode
            if stat.S_ISLNK(mode):
                raise RuntimeError(f"Refusing to archive symbolic link: {path}")
        for name in files:
            path = os.path.join(root, name)
            relative = os.path.relpath(path, source)
            archive.write(path, os.path.join("config", relative))
PYTHON

mv "$temp_archive" "$archive"
if ((was_active)); then
  systemctl start "$service"
  was_active=0
fi
trap - EXIT
printf 'Created Seerr backup: %s\n' "$archive"
