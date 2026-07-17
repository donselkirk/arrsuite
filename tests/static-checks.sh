#!/usr/bin/env bash
set -Eeuo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ct_script="${project_root}/ct/arrsuite.sh"
bootstrap_script="${project_root}/arrsuite.sh"
install_script="${project_root}/install/arrsuite-install.sh"
json_file="${project_root}/json/arrsuite.json"
release_workflow="${project_root}/.github/workflows/release.yml"
upstream_workflow="${project_root}/.github/workflows/upstream-check.yml"
wiki_workflow="${project_root}/.github/workflows/wiki.yml"
artifact_builder="${project_root}/tools/build-artifacts.sh"
upstream_checker="${project_root}/tools/check-upstream.sh"
upstream_lock="${project_root}/tools/upstream-lock.json"
manager_template="${project_root}/src/arrsuite-manager.sh.in"
installer_template="${project_root}/src/arrsuite-install.sh.in"
manager_tmp="$(mktemp)"
motd_tmp="$(mktemp)"
template_tmp_dir="$(mktemp -d)"
standalone_manager="${project_root}/tools/arrsuite-manager"
behavior_test="${project_root}/tests/manager-behavior.sh"
standalone_motd="${project_root}/tools/arrsuite-motd.sh"
seerr_backup_tool="${project_root}/tools/seerr-backup.sh"
trap 'rm -f "$manager_tmp" "$motd_tmp"; rm -rf "$template_tmp_dir"' EXIT

"$artifact_builder" --check

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
bash -n "$artifact_builder"
bash -n "$upstream_checker"
bash -n "$manager_template"
bash -n "$installer_template"
for template_script in "${project_root}/templates/update.sh"; do
  bash -n "$template_script"
done
for module in "${project_root}"/apps/*.sh; do
  bash -n "$module"
  app="$(basename "$module" .sh)"
  grep -q "write_${app}_service()" "$module"
  grep -q "install_${app}()" "$module"
  grep -q "update_${app}()" "$module"
done

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

printf 'Checking generated templates...\n'
for app in sonarr radarr lidarr prowlarr byparr flaresolverr seerr bazarr; do
  awk -v target="/etc/systemd/system/${app}.service" '
    index($0, "cat > " target " <<") { capture=1; next }
    capture && /^EOF_SERVICE$/ { exit }
    capture
  ' "$standalone_manager" >"${template_tmp_dir}/${app}.service"
  cmp -s "${template_tmp_dir}/${app}.service" "${project_root}/templates/systemd/${app}.service" || {
    echo "Generated ${app} service does not match its source template." >&2
    exit 1
  }
done
awk '
  /cat > \/etc\/seerr\/seerr.conf <</ { capture=1; next }
  capture && /^EOF_CONFIG$/ { exit }
  capture
' "$standalone_manager" >"${template_tmp_dir}/seerr.conf"
cmp -s "${template_tmp_dir}/seerr.conf" "${project_root}/templates/config/seerr.conf" || {
  echo "Generated Seerr configuration does not match its source template." >&2
  exit 1
}
for getty in container-getty console-getty; do
  marker="EOF_GETTY"
  service_path="container-getty@1"
  [[ "$getty" != "console-getty" ]] || marker="EOF_CONSOLE"
  [[ "$getty" != "console-getty" ]] || service_path="console-getty"
  awk -v service="$service_path" -v marker="$marker" '
    index($0, service ".service.d/override.conf <<") { capture=1; next }
    capture && $0 == marker { exit }
    capture
  ' "$install_script" >"${template_tmp_dir}/${getty}.override.conf"
  cmp -s "${template_tmp_dir}/${getty}.override.conf" \
    "${project_root}/templates/getty/${getty}.override.conf" || {
    echo "Generated ${getty} override does not match its source template." >&2
    exit 1
  }
done
awk '
  /cat >\/usr\/bin\/update <</ { capture=1; next }
  capture && /^EOF_UPDATE$/ { exit }
  capture
' "$install_script" >"${template_tmp_dir}/update.sh"
cmp -s "${template_tmp_dir}/update.sh" "${project_root}/templates/update.sh" || {
  echo "Generated update wrapper does not match its source template." >&2
  exit 1
}

printf 'Checking JSON metadata...\n'
python3 -m json.tool "$json_file" >/dev/null
python3 -m json.tool "$upstream_lock" >/dev/null

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
grep -q 'remove_or_reset_apps()' "$install_script"
grep -q 'remove_app_files()' "$install_script"
grep -q 'arrsuite remove app' "$install_script"
grep -q 'arrsuite reset app' "$install_script"
grep -q 'require_installed_app()' "$install_script"
grep -q 'Unknown command: $1' "$install_script"
grep -q '^trap - ERR$' "$install_script"
grep -q '^main "$@"$' "$install_script"
grep -q 'SHA256SUMS' "$install_script"
grep -q 'staged_prebuilt_update()' "$install_script"
grep -q 'arrsuite restart \[app ...\]' "$install_script"
grep -q 'fetch_and_deploy_gh_release' "$install_script"
grep -q 'community-tools.sh' "$install_script"
grep -q 'apt install -y python3 whiptail' "$install_script"
grep -q 'SUPPORTED_APPS=(sonarr radarr lidarr prowlarr byparr flaresolverr seerr bazarr)' "$install_script"
grep -q 'conflicting_app()' "$install_script"
grep -q 'Byparr.*cannot be installed with.*FlareSolverr\|cannot be installed with.*APP_LABEL' "$install_script"
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
if grep -q 'Creating Pre-Restore Safety Backup\|backups/pre-restore' "$install_script"; then
  echo "Restore operations must not create automatic safety backups." >&2
  exit 1
fi
grep -q 'create_seerr_backup()' "$install_script"
grep -q 'restore_seerr_backup()' "$install_script"
grep -q 'create_bazarr_backup()' "$install_script"
grep -q 'restore_bazarr_backup()' "$install_script"
grep -q '\[prowlarr\]="v1"' "$install_script"
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
if grep -q '^    paths:$' "$release_workflow"; then
  echo "Every push to main must run validation and create a release." >&2
  exit 1
fi
grep -q 'bash tests/static-checks.sh' "$release_workflow"
grep -q 'bash tools/build-artifacts.sh' "$release_workflow"
grep -q 'git diff --exit-code' "$release_workflow"
grep -q 'gh release create' "$release_workflow"
grep -q 'dist/arrsuite-install.sh' "$release_workflow"
grep -q 'dist/seerr-backup.sh' "$release_workflow"
grep -q -- '--docker CONTAINER' "$seerr_backup_tool"
grep -q 'docker stop' "$seerr_backup_tool"
grep -q 'docker cp' "$seerr_backup_tool"
grep -q 'docker start' "$seerr_backup_tool"
grep -q 'os.path.islink' "$seerr_backup_tool"
grep -q 'dist/VERSION' "$release_workflow"
grep -q '^name: Check Community Scripts Upstream$' "$upstream_workflow"
grep -q 'schedule:' "$upstream_workflow"
grep -q 'bash tools/check-upstream.sh' "$upstream_workflow"
grep -q 'actions/upload-artifact@v4' "$upstream_workflow"
grep -q '^name: Publish Wiki$' "$wiki_workflow"
grep -q '      - "wiki/\*\*/\*.md"' "$wiki_workflow"
grep -q '\.wiki\.git' "$wiki_workflow"
grep -q 'cp wiki/\*\.md' "$wiki_workflow"
grep -q 'git push origin HEAD:master' "$wiki_workflow"
for wiki_page in User-Guide Backup-and-Restore Console-and-Troubleshooting Architecture Building-and-Development Upstream-Integration; do
  [[ -s "${project_root}/wiki/${wiki_page}.md" ]]
  grep -q "arrsuite/wiki/${wiki_page}" "${project_root}/README.md"
done
[[ -s "${project_root}/wiki/Home.md" ]]
grep -q 'ARRSUITE_APP_MODULES' "$manager_template"
grep -q 'community-scripts/ProxmoxVED' "$upstream_lock"
grep -q 'community-scripts/ProxmoxVE' "$upstream_lock"
if grep -Eq '(^|[^[:alnum:]])v[0-9]+\.[0-9]+' "${project_root}/README.md"; then
  echo "README must not hard-code an ArrSuite version number." >&2
  exit 1
fi
if grep -q 'ARRSUITE_RELEASE_BASE_URL' "${project_root}/README.md"; then
  echo "Version-pinned installation belongs in development documentation, not README." >&2
  exit 1
fi
grep -q '^export ARRSUITE_RELEASE_BASE_URL=' "${project_root}/wiki/Building-and-Development.md"
grep -q 'curl -fsSL "${ARRSUITE_RELEASE_BASE_URL}/arrsuite.sh"' "${project_root}/wiki/Building-and-Development.md"
grep -q '^export ARRSUITE_RELEASE_BASE_URL=' "${project_root}/AGENTS.md"
grep -q 'curl -fsSL "${ARRSUITE_RELEASE_BASE_URL}/arrsuite.sh"' "${project_root}/AGENTS.md"

printf 'Running manager behavior tests...\n'
bash "$behavior_test"

if command -v shellcheck >/dev/null 2>&1; then
  printf 'Running ShellCheck...\n'
  # SC1090/SC1091: function libraries are generated or downloaded at runtime.
  shellcheck -e SC1090,SC1091 "$bootstrap_script" "$ct_script" "$install_script" "$installer_template" "$manager_tmp" "$standalone_manager" "$motd_tmp" "$standalone_motd" "$behavior_test" "${project_root}/templates/update.sh" "${project_root}/tools/fix-console-autologin.sh" "$seerr_backup_tool" "$artifact_builder" "$upstream_checker"
else
  printf 'ShellCheck not installed; skipping it.\n'
fi

printf 'All static checks passed.\n'
