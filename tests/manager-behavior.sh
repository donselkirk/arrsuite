#!/usr/bin/env bash
set -Eeuo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manager="${project_root}/tools/arrsuite-manager"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/bin" "$test_root/lib" "$test_root/run" "$test_root/runtime" \
  "$test_root/app-data/sonarr" "$test_root/app-data/radarr" "$test_root/seerr-config/db" \
  "$test_root/seerr-config/logs"
printf 'seerr-database-fixture\n' >"$test_root/seerr-config/db/db.sqlite3"
printf '{"initialized":true}\n' >"$test_root/seerr-config/settings.json"
ln -s /tmp/seerr-machine-logs.json "$test_root/seerr-config/logs/.machinelogs.json"
for app in sonarr radarr; do
  cat >"$test_root/app-data/$app/config.xml" <<'EOF_CONFIG'
<Config>
  <UrlBase></UrlBase>
  <ApiKey>test-api-key</ApiKey>
</Config>
EOF_CONFIG
done
cat >"$test_root/lib/community-functions.sh" <<'EOF_FUNCTIONS'
color() { :; }
msg_info() { :; }
msg_ok() { printf '%s\n' "$*"; }
msg_warn() { :; }
msg_error() { :; }
arch_resolve() { printf '%s' "$1"; }
EOF_FUNCTIONS
cat >"$test_root/lib/community-tools.sh" <<'EOF_TOOLS'
fetch_and_deploy_gh_release() { return 1; }
check_for_gh_release() { return 1; }
setup_uv() { return 1; }
EOF_TOOLS
cat >"$test_root/bin/curl" <<'EOF_CURL'
#!/usr/bin/env bash
set -e
url=""
output=""
method="GET"
while (($#)); do
  case "$1" in
    -o) output="$2"; shift 2 ;;
    -X) method="$2"; shift 2 ;;
    -H|-d|-F) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
case "$url" in
  */api/v3/command/42) printf '{"status":"completed"}\n'; exit 0 ;;
  */api/v3/command)
    [[ "$method" == "POST" ]] || exit 22
    printf '{"id":42}\n'
    exit 0
    ;;
  *:8989/api/v3/system/backup)
    printf '[{"type":"manual","path":"/backup/manual/sonarr_backup_test.zip","name":"sonarr_backup_test.zip","time":"2099-01-01T00:00:00Z"}]\n'
    exit 0
    ;;
  *:7878/api/v3/system/backup)
    printf '[{"type":"manual","path":"/backup/manual/radarr_backup_test.zip","name":"radarr_backup_test.zip","time":"2099-01-01T00:00:00Z"}]\n'
    exit 0
    ;;
  */api/v3/system/backup/restore/upload) printf '{"restartRequired":true}\n'; exit 0 ;;
  */backup/manual/*)
    app="sonarr"
    [[ "$url" == *radarr* ]] && app="radarr"
    python3 - "$output" "$app" <<'PYTHON'
import sys
import zipfile
with zipfile.ZipFile(sys.argv[1], "w") as archive:
    archive.writestr(f"{sys.argv[2]}.db", "native-backup-fixture\n")
    archive.writestr("config.xml", "<Config />\n")
PYTHON
    exit 0
    ;;
  */arrsuite-manager) source_file="${PROJECT_ROOT}/tools/arrsuite-manager" ;;
  */arrsuite-motd.sh) source_file="${PROJECT_ROOT}/tools/arrsuite-motd.sh" ;;
  */fix-console-autologin.sh) source_file="${PROJECT_ROOT}/tools/fix-console-autologin.sh" ;;
  */VERSION) printf 'v9.8.7\n' >"$output"; exit 0 ;;
  */misc/install.func) source_file="${TEST_ROOT}/lib/community-functions.sh" ;;
  */misc/tools.func) source_file="${TEST_ROOT}/lib/community-tools.sh" ;;
  *) exit 22 ;;
esac
cp "$source_file" "$output"
EOF_CURL
chmod 0755 "$test_root/bin/curl"
cat >"$test_root/bin/systemctl" <<'EOF_SYSTEMCTL'
#!/usr/bin/env bash
if [[ "${1:-}" == "restart" ]]; then
  printf '%s\n' "${2:-}" >>"${TEST_ROOT}/restarts.log"
  [[ "${2:-}" == "${SYSTEMCTL_FAIL_SERVICE:-}" ]] && exit 1
fi
[[ " $* " == *" is-active "* ]] && printf 'active\n'
exit 0
EOF_SYSTEMCTL
chmod 0755 "$test_root/bin/systemctl"
cat >"$test_root/bin/docker" <<'EOF_DOCKER'
#!/usr/bin/env bash
set -e
case "${1:-}" in
  inspect)
    if [[ "${2:-}" == "--format" ]]; then
      printf 'true\n'
    fi
    ;;
  stop)
    printf 'stop %s\n' "$2" >>"${TEST_ROOT}/docker.log"
    ;;
  start)
    printf 'start %s\n' "$2" >>"${TEST_ROOT}/docker.log"
    ;;
  cp)
    cp -a "${TEST_ROOT}/seerr-config" "${3%/}/config"
    ;;
  *) exit 2 ;;
esac
EOF_DOCKER
chmod 0755 "$test_root/bin/docker"

run_manager() {
  ARRSUITE_BASE_DIR="$test_root" \
    ARRSUITE_ALLOW_NON_ROOT=1 \
    ARRSUITE_SKIP_SELF_UPDATE=1 \
    ARRSUITE_FUNCTIONS_LIBRARY="$test_root/lib/community-functions.sh" \
    ARRSUITE_TOOLS_LIBRARY="$test_root/lib/community-tools.sh" \
    ARRSUITE_LOCK_FILE="$test_root/run/arrsuite.lock" \
    ARRSUITE_MANAGER_PATH="$test_root/runtime/arrsuite" \
    ARRSUITE_MOTD_PATH="$test_root/runtime/arrsuite-motd.sh" \
    ARRSUITE_REPAIR_PATH="$test_root/runtime/fix-console-autologin.sh" \
    ARRSUITE_APP_DATA_ROOT="$test_root/app-data" \
    ARRSUITE_SEERR_CONFIG_DIR="$test_root/seerr-config" \
    PROJECT_ROOT="$project_root" \
    TEST_ROOT="$test_root" \
    PATH="$test_root/bin:$PATH" \
    "$manager" "$@"
}

list_output="$(run_manager list)"
grep -q '^Sonarr[[:space:]]\+no[[:space:]]\+8989' <<<"$list_output"
grep -q '^Radarr[[:space:]]\+no[[:space:]]\+7878' <<<"$list_output"
grep -q '^Lidarr[[:space:]]\+no[[:space:]]\+8686' <<<"$list_output"
grep -q '^Prowlarr[[:space:]]\+no[[:space:]]\+9696' <<<"$list_output"
grep -q '^Byparr[[:space:]]\+no[[:space:]]\+8191' <<<"$list_output"
grep -q '^FlareSolverr[[:space:]]\+no[[:space:]]\+8192' <<<"$list_output"
grep -q '^Seerr[[:space:]]\+no[[:space:]]\+5055' <<<"$list_output"
grep -q '^Bazarr[[:space:]]\+no[[:space:]]\+6767' <<<"$list_output"

if STD=false run_manager add sonarr; then
  echo "A failed install unexpectedly succeeded." >&2
  exit 1
fi
[[ ! -s "$test_root/installed.apps" ]] || {
  echo "A failed install was written to installed.apps." >&2
  exit 1
}

printf '%s\n' sonarr radarr >"$test_root/installed.apps"
if run_manager update lidarr; then
  echo "A targeted update of an uninstalled app unexpectedly succeeded." >&2
  exit 1
fi

status_output="$(run_manager help)"
grep -q 'arrsuite update \[app ...\]' <<<"$status_output"
grep -q 'arrsuite restart \[app ...\]' <<<"$status_output"
grep -q 'arrsuite backup \[app ...\]' <<<"$status_output"
grep -q 'arrsuite restore app backup.zip' <<<"$status_output"

if run_manager backup bazarr; then
  echo "An unsupported native backup unexpectedly succeeded." >&2
  exit 1
fi

run_manager backup sonarr radarr --output "$test_root/backups"
python3 -m zipfile -t "$test_root/backups/sonarr/sonarr_backup_test.zip"
python3 -m zipfile -t "$test_root/backups/radarr/radarr_backup_test.zip"
run_manager restore sonarr "$test_root/backups/sonarr/sonarr_backup_test.zip"
python3 -m zipfile -t "$test_root/backups/pre-restore/sonarr/sonarr_backup_test.zip"
run_manager restore radarr "$test_root/backups/radarr/radarr_backup_test.zip"
python3 -m zipfile -t "$test_root/backups/pre-restore/radarr/radarr_backup_test.zip"

printf '%s\n' sonarr radarr seerr >"$test_root/installed.apps"
run_manager backup seerr --output "$test_root/backups"
seerr_backup="$(find "$test_root/backups/seerr" -maxdepth 1 -name 'arrsuite_seerr_backup_*.zip' -print -quit)"
[[ -n "$seerr_backup" ]]
python3 -m zipfile -t "$seerr_backup"
run_manager restore seerr "$seerr_backup"
python3 -m zipfile -t "$(find "$test_root/backups/pre-restore/seerr" -maxdepth 1 -name 'arrsuite_seerr_backup_*.zip' -print -quit)"

mkdir -p "$test_root/external-seerr-backups"
SEERR_CONFIG_DIR="$test_root/seerr-config" \
  SEERR_BACKUP_ALLOW_NON_ROOT=1 \
  TEST_ROOT="$test_root" \
  PATH="$test_root/bin:$PATH" \
  bash "$project_root/tools/seerr-backup.sh" "$test_root/external-seerr-backups"
external_seerr_backup="$(find "$test_root/external-seerr-backups" -maxdepth 1 -name 'arrsuite_seerr_backup_*.zip' -print -quit)"
[[ -n "$external_seerr_backup" ]]
run_manager restore seerr "$external_seerr_backup"

mkdir -p "$test_root/docker-seerr-backups"
: >"$test_root/docker.log"
SEERR_BACKUP_ALLOW_NON_ROOT=1 \
  TEST_ROOT="$test_root" \
  PATH="$test_root/bin:$PATH" \
  bash "$project_root/tools/seerr-backup.sh" --docker seerr-container "$test_root/docker-seerr-backups"
docker_seerr_backup="$(find "$test_root/docker-seerr-backups" -maxdepth 1 -name 'arrsuite_seerr_backup_*.zip' -print -quit)"
[[ -n "$docker_seerr_backup" ]]
python3 - "$docker_seerr_backup" <<'PYTHON'
import sys
import zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    assert "config/logs/.machinelogs.json" not in archive.namelist()
PYTHON
grep -qx 'stop seerr-container' "$test_root/docker.log"
grep -qx 'start seerr-container' "$test_root/docker.log"
run_manager restore seerr "$docker_seerr_backup"
python3 - "$test_root/invalid-seerr.zip" <<'PYTHON'
import sys
import zipfile
with zipfile.ZipFile(sys.argv[1], "w") as archive:
    archive.writestr("config/db/db.sqlite3", "invalid-without-manifest")
PYTHON
if run_manager restore seerr "$test_root/invalid-seerr.zip"; then
  echo "An invalid Seerr backup unexpectedly restored successfully." >&2
  exit 1
fi

run_manager restart sonarr
run_manager restart
if run_manager restart lidarr; then
  echo "Restarting an uninstalled application unexpectedly succeeded." >&2
  exit 1
fi
: >"$test_root/restarts.log"
if SYSTEMCTL_FAIL_SERVICE=sonarr run_manager restart; then
  echo "A failed application restart unexpectedly returned success." >&2
  exit 1
fi
grep -qx 'radarr' "$test_root/restarts.log"

self_update_output="$(run_manager self-update)"
grep -q 'Updated ArrSuite Runtime to v9.8.7' <<<"$self_update_output"
current_output="$(run_manager self-update)"
grep -q 'ArrSuite Runtime is Already Current at v9.8.7' <<<"$current_output"
cmp -s "$manager" "$test_root/runtime/arrsuite"
cmp -s "$project_root/tools/arrsuite-motd.sh" "$test_root/runtime/arrsuite-motd.sh"
cmp -s "$project_root/tools/fix-console-autologin.sh" "$test_root/runtime/fix-console-autologin.sh"
grep -qx 'v9.8.7' "$test_root/version"
grep -q 'ArrSuite v9.8.7' < <(run_manager version)

printf 'Manager behavior checks passed.\n'
