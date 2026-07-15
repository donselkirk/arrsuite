#!/usr/bin/env bash
set -Eeuo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manager="${project_root}/tools/arrsuite-manager"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

mkdir -p "$test_root/bin" "$test_root/lib" "$test_root/run" "$test_root/runtime" \
  "$test_root/app-data/sonarr" "$test_root/app-data/radarr"
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
[[ " $* " == *" is-active "* ]] && printf 'active\n'
exit 0
EOF_SYSTEMCTL
chmod 0755 "$test_root/bin/systemctl"

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
