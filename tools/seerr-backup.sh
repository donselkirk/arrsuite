#!/usr/bin/env bash
set -Eeuo pipefail

[[ $EUID -eq 0 || "${SEERR_BACKUP_ALLOW_NON_ROOT:-0}" == "1" ]] || {
  echo "Run this script as root in the Seerr LXC or on the Docker host." >&2
  exit 1
}

command -v python3 >/dev/null 2>&1 || {
  echo "python3 is required to create the backup archive." >&2
  exit 1
}

docker_mode=0
docker_container=""
docker_stopped=0
source_temp=""
service=""
was_active=0

if [[ "${1:-}" == "--docker" ]]; then
  (($# >= 2 && $# <= 3)) || {
    echo "Usage: seerr-backup.sh --docker CONTAINER [OUTPUT_DIRECTORY]" >&2
    exit 2
  }
  docker_mode=1
  docker_container="$2"
  output_dir="${3:-$PWD}"
  command -v docker >/dev/null 2>&1 || {
    echo "docker is required for --docker mode." >&2
    exit 1
  }
  docker inspect "$docker_container" >/dev/null 2>&1 || {
    echo "Docker container not found: ${docker_container}" >&2
    exit 1
  }
  [[ "$(docker inspect --format '{{.State.Running}}' "$docker_container")" == "true" ]] || {
    echo "Docker container must be running: ${docker_container}" >&2
    exit 1
  }
  source_temp="$(mktemp -d)"
  config_dir="${source_temp}/config"
else
  (($# <= 1)) || {
    echo "Usage: seerr-backup.sh [OUTPUT_DIRECTORY]" >&2
    echo "       seerr-backup.sh --docker CONTAINER [OUTPUT_DIRECTORY]" >&2
    exit 2
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
  systemctl is-active --quiet "$service" && was_active=1
fi

install -d -m 0750 "$output_dir"
timestamp="$(date +%Y.%m.%d_%H.%M.%S)"
archive="${output_dir%/}/arrsuite_seerr_backup_${timestamp}.zip"
temp_archive="$(mktemp "${output_dir%/}/.seerr-backup.XXXXXX")"

cleanup() {
  rm -f "$temp_archive"
  [[ -z "$source_temp" ]] || rm -rf "$source_temp"
  if ((docker_stopped)); then
    docker start "$docker_container" >/dev/null 2>&1 || true
  elif ((was_active)); then
    systemctl start "$service" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if ((docker_mode)); then
  printf 'Stopping Docker container %s for a consistent SQLite backup...\n' "$docker_container"
  docker stop "$docker_container" >/dev/null
  docker_stopped=1
  docker cp "${docker_container}:${SEERR_DOCKER_CONFIG_PATH:-/app/config}" "$source_temp/"
elif ((was_active)); then
  printf 'Stopping %s for a consistent SQLite backup...\n' "$service"
  systemctl stop "$service"
fi

[[ -f "$config_dir/db/db.sqlite3" ]] || {
  echo "Only Seerr SQLite installations are supported; db/db.sqlite3 was not found." >&2
  exit 1
}

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
if ((docker_stopped)); then
  docker start "$docker_container" >/dev/null
  docker_stopped=0
elif ((was_active)); then
  systemctl start "$service"
  was_active=0
fi
[[ -z "$source_temp" ]] || rm -rf "$source_temp"
source_temp=""
trap - EXIT
printf 'Created Seerr backup: %s\n' "$archive"
