#!/usr/bin/env bash
set -Eeuo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ct_script="${project_root}/ct/arrsuite.sh"
bootstrap_script="${project_root}/arrsuite.sh"
install_script="${project_root}/install/arrsuite-install.sh"
json_file="${project_root}/json/arrsuite.json"
release_workflow="${project_root}/.github/workflows/release.yml"
manager_tmp="$(mktemp)"
motd_tmp="$(mktemp)"
standalone_manager="${project_root}/tools/arrsuite-manager"
behavior_test="${project_root}/tests/manager-behavior.sh"
standalone_motd="${project_root}/tools/arrsuite-motd.sh"
seerr_backup_tool="${project_root}/tools/seerr-backup.sh"
trap 'rm -f "$manager_tmp" "$motd_tmp"' EXIT

printf 'Checking Bash syntax...\n'
bash -n "$ct_script"
bash -n "$bootstrap_script"
bash -n "$install_script"

awk '
  /^cat > \/usr\/local\/bin\/arrsuite <<'"'"'EOF_MANAGER'"'"'$/ { capture=1; next }
  /^EOF_MANAGER$/ { capture=0 }
  capture
' "$install_script" >"$manager_tmp"

[[ -s "$manager_tmp" ]] || {
  echo "Unable to extract embedded arrsuite manager." >&2
  exit 1
}
bash -n "$manager_tmp"
bash -n "$standalone_manager"
bash -n "$behavior_test"
bash -n "$standalone_motd"
bash -n "$seerr_backup_tool"

awk '
  /^  cat >\/etc\/profile\.d\/00_lxc-details\.sh <<'"'"'EOF_MOTD'"'"'$/ { capture=1; next }
  /^EOF_MOTD$/ { capture=0 }
  capture
' "$install_script" >"$motd_tmp"
[[ -s "$motd_tmp" ]] || {
  echo "Unable to extract the ArrSuite login banner." >&2
  exit 1
}
bash -n "$motd_tmp"
cmp -s "$motd_tmp" "$standalone_motd" || {
  echo "Standalone ArrSuite login banner is out of sync with the installer." >&2
  exit 1
}
cmp -s "$manager_tmp" "$standalone_manager" || {
  echo "Standalone ArrSuite manager is out of sync with the embedded manager." >&2
  exit 1
}

printf 'Checking JSON metadata...\n'
python3 -m json.tool "$json_file" >/dev/null

printf 'Checking required project files...\n'
for required in "$bootstrap_script" "$ct_script" "$install_script" "$json_file" "$standalone_manager" "$seerr_backup_tool"; do
  [[ -s "$required" ]] || {
    echo "Missing required file: $required" >&2
    exit 1
  }
done

grep -q 'function update_script()' "$ct_script"
grep -q 'var_nesting="${var_nesting:-0}"' "$ct_script"
grep -q 'var_ram="${var_ram:-6144}"' "$ct_script"
grep -q 'var_disk="${var_disk:-16}"' "$ct_script"
grep -q 'ARRSUITE_BUILD_FUNC_PATH' "$ct_script"
grep -q 'ARRSUITE_INSTALL_URL' "$bootstrap_script"
grep -q 'releases/latest/download' "$bootstrap_script"
grep -q 'ARRSUITE_REPOSITORY_RAW_URL' "$bootstrap_script"
if grep -Eq '^set -[^[:space:]]*u' "$bootstrap_script"; then
  echo "The bootstrap must not enable nounset; Community Scripts uses optional unset variables." >&2
  exit 1
fi
grep -q '^set +u$' "$bootstrap_script" || {
  echo "The bootstrap must explicitly disable inherited nounset." >&2
  exit 1
}
bash -u -c 'source <(sed -n "1,5p" "$1"); [[ $- != *u* ]]' _ "$bootstrap_script"
grep -q 'arrsuite update' "$ct_script"
grep -q 'restart_apps()' "$install_script"
grep -q 'arrsuite restart \[app ...\]' "$install_script"
grep -q 'fetch_and_deploy_gh_release' "$install_script"
grep -q 'community-tools.sh' "$install_script"
grep -q 'apt install -y python3 whiptail' "$install_script"
grep -q 'SUPPORTED_APPS=(sonarr radarr lidarr prowlarr byparr flaresolverr seerr bazarr)' "$install_script"
grep -q 'install_lidarr()' "$install_script"
grep -q 'update_lidarr()' "$install_script"
grep -q 'Lidarr.master\*linux-core-' "$install_script"
grep -q 'lidarr.service' "$install_script"
grep -q '8686' "$install_script"
grep -q 'install_prowlarr()' "$install_script"
grep -q 'update_prowlarr()' "$install_script"
grep -q 'Prowlarr.master\*linux-core-x64' "$install_script"
grep -q 'prowlarr.service' "$install_script"
grep -q '9696' "$install_script"
grep -q 'install_flaresolverr()' "$install_script"
grep -q 'update_flaresolverr()' "$install_script"
grep -q 'flaresolverr_linux_x64.tar.gz' "$install_script"
grep -q 'flaresolverr.service' "$install_script"
grep -q 'Environment="PORT=8192"' "$install_script"
grep -q 'install_seerr()' "$install_script"
grep -q 'update_seerr()' "$install_script"
grep -q 'seerr-team/seerr' "$install_script"
grep -q 'seerr.service' "$install_script"
grep -q 'PORT=5055' "$install_script"
grep -q 'NODE_VERSION="22"' "$install_script"
grep -q 'install_bazarr()' "$install_script"
grep -q 'update_bazarr()' "$install_script"
grep -q 'morpheus65535/bazarr' "$install_script"
grep -q 'bazarr.zip' "$install_script"
grep -q 'bazarr.service' "$install_script"
grep -q 'PYTHON_VERSION="3.12"' "$install_script"
grep -q '\[\[ "$app" == "lidarr" || "$app" == "prowlarr" || "$app" == "byparr" || "$app" == "flaresolverr" || "$app" == "seerr" || "$app" == "bazarr" \]\] && default_state="OFF"' "$install_script"
grep -q 'check_for_gh_release' "$install_script"
grep -q 'self_update()' "$install_script"
grep -q 'Updated ArrSuite Runtime to ${release_version}' "$install_script"
grep -q 'ArrSuite Runtime is Already Current at ${release_version}' "$install_script"
grep -q 'arrsuite self-update' "$install_script"
grep -q 'releases/latest/download' "$install_script"
grep -q 'arrsuite version' "$install_script"
grep -q 'arrsuite backup \[app ...\] \[--output directory\]' "$install_script"
grep -q 'arrsuite restore app backup.zip' "$install_script"
grep -q 'create_native_backup()' "$install_script"
grep -q 'restore_native_backup()' "$install_script"
grep -q '\[lidarr\]="v1"' "$install_script"
grep -q 'validate_backup_zip()' "$install_script"
grep -q '/system/backup/restore/upload' "$install_script"
grep -q 'Creating Pre-Restore Safety Backup' "$install_script"
grep -q 'create_seerr_backup()' "$install_script"
grep -q 'restore_seerr_backup()' "$install_script"
grep -q 'self-update failed; continuing with application updates' "$install_script"
if grep -q 'return 130' "$install_script"; then
  echo "Checklist cancellation must not trigger the global error handler." >&2
  exit 1
fi
grep -A3 'mapfile -t apps.*choose_uninstalled_apps' "$install_script" \
  | grep -q "printf '\\\\033\[2J\\\\033\[H' >/dev/tty" || {
  echo "The parent manager must clear the terminal after the checklist exits." >&2
  exit 1
}
grep -q 'setup_uv' "$install_script"
grep -q 'configure_arrsuite_console_autologin' "$install_script"
grep -q '^configure_arrsuite_console_autologin$' "$install_script"
grep -q 'configure_arrsuite_motd' "$install_script"
grep -q '/opt/arrsuite/installed.apps' "$install_script"
grep -q 'Installed Applications:' "$install_script"
grep -q ': >/etc/motd' "$install_script"
if grep -q 'msg_info "Selecting ArrSuite Applications"' "$install_script"; then
  echo "Do not run a spinner behind the interactive application checklist." >&2
  exit 1
fi
grep -q 'container-getty@1.service.d/override.conf' "$install_script"
grep -q 'console-getty.service.d/override.conf' "$install_script"
grep -q 'systemctl restart container-getty@1.service' "$install_script"
grep -q 'systemctl restart console-getty.service' "$install_script"
if [[ "$(grep -c '^ImportCredential=$' "$install_script")" -lt 2 ]]; then
  echo "Both getty overrides must clear Debian 13 systemd credentials." >&2
  exit 1
fi
if grep -q 'systemctl try-restart.*getty' "$install_script"; then
  echo "Console gettys must start even when they were initially inactive." >&2
  exit 1
fi
grep -q 'exec /usr/local/bin/arrsuite update' "$install_script"
bash -n "${project_root}/tools/fix-console-autologin.sh"

printf 'Checking release workflow...\n'
[[ -s "$release_workflow" ]]
grep -q '^name: Validate and Release$' "$release_workflow"
grep -q '^    paths:$' "$release_workflow"
grep -q '      - "arrsuite.sh"' "$release_workflow"
grep -q '      - "ct/\*\*/\*.sh"' "$release_workflow"
grep -q '      - "install/\*\*/\*.sh"' "$release_workflow"
grep -q '      - "tools/arrsuite-manager"' "$release_workflow"
grep -q '      - "tools/\*\*/\*.sh"' "$release_workflow"
if grep -Eq 'README|AGENTS' "$release_workflow"; then
  echo "Documentation files must not trigger validation and releases." >&2
  exit 1
fi
grep -q 'bash tests/static-checks.sh' "$release_workflow"
grep -q 'gh release create' "$release_workflow"
grep -q 'dist/arrsuite-install.sh' "$release_workflow"
grep -q 'dist/seerr-backup.sh' "$release_workflow"
grep -q -- '--docker CONTAINER' "$seerr_backup_tool"
grep -q 'docker stop' "$seerr_backup_tool"
grep -q 'docker cp' "$seerr_backup_tool"
grep -q 'docker start' "$seerr_backup_tool"
grep -q 'os.path.islink' "$seerr_backup_tool"
grep -q 'dist/VERSION' "$release_workflow"
if grep -Eq '(^|[^[:alnum:]])v[0-9]+\.[0-9]+' "${project_root}/README.md"; then
  echo "README must not hard-code an ArrSuite version number." >&2
  exit 1
fi

printf 'Running manager behavior tests...\n'
bash "$behavior_test"

if command -v shellcheck >/dev/null 2>&1; then
  printf 'Running ShellCheck...\n'
  # SC1090/SC1091: function libraries are generated or downloaded at runtime.
  shellcheck -e SC1090,SC1091 "$bootstrap_script" "$ct_script" "$install_script" "$manager_tmp" "$standalone_manager" "$motd_tmp" "$standalone_motd" "$behavior_test" "${project_root}/tools/fix-console-autologin.sh" "$seerr_backup_tool"
else
  printf 'ShellCheck not installed; skipping it.\n'
fi

printf 'All static checks passed.\n'
