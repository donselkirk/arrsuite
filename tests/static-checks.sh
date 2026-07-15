#!/usr/bin/env bash
set -Eeuo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ct_script="${project_root}/ct/arrsuite.sh"
bootstrap_script="${project_root}/arrsuite.sh"
install_script="${project_root}/install/arrsuite-install.sh"
json_file="${project_root}/json/arrsuite.json"
manager_tmp="$(mktemp)"
standalone_manager="${project_root}/tools/arrsuite-manager"
behavior_test="${project_root}/tests/manager-behavior.sh"
trap 'rm -f "$manager_tmp"' EXIT

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
cmp -s "$manager_tmp" "$standalone_manager" || {
  echo "Standalone ArrSuite manager is out of sync with the embedded manager." >&2
  exit 1
}

printf 'Checking JSON metadata...\n'
python3 -m json.tool "$json_file" >/dev/null

printf 'Checking required project files...\n'
for required in "$bootstrap_script" "$ct_script" "$install_script" "$json_file" "$standalone_manager"; do
  [[ -s "$required" ]] || {
    echo "Missing required file: $required" >&2
    exit 1
  }
done

grep -q 'function update_script()' "$ct_script"
grep -q 'ARRSUITE_BUILD_FUNC_PATH' "$ct_script"
grep -q 'ARRSUITE_INSTALL_URL' "$bootstrap_script"
grep -q 'donselkirk/arrsuite/main' "$bootstrap_script"
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
grep -q 'fetch_and_deploy_gh_release' "$install_script"
grep -q 'SUPPORTED_APPS=(sonarr radarr lidarr byparr)' "$install_script"
grep -q 'install_lidarr()' "$install_script"
grep -q 'update_lidarr()' "$install_script"
grep -q 'Lidarr.master\*linux-core-' "$install_script"
grep -q 'lidarr.service' "$install_script"
grep -q '8686' "$install_script"
grep -q '\[\[ "$app" == "lidarr" || "$app" == "byparr" \]\] && default_state="OFF"' "$install_script"
grep -q 'check_for_gh_release' "$install_script"
grep -q 'setup_uv' "$install_script"
grep -q 'configure_arrsuite_console_autologin' "$install_script"
grep -q 'container-getty@1.service.d/override.conf' "$install_script"
grep -q 'console-getty.service.d/override.conf' "$install_script"
grep -q 'exec /usr/local/bin/arrsuite update' "$install_script"
bash -n "${project_root}/tools/fix-console-autologin.sh"

printf 'Running manager behavior tests...\n'
bash "$behavior_test"

if command -v shellcheck >/dev/null 2>&1; then
  printf 'Running ShellCheck...\n'
  # SC1090/SC1091: function libraries are generated or downloaded at runtime.
  shellcheck -e SC1090,SC1091 "$bootstrap_script" "$ct_script" "$install_script" "$manager_tmp" "$standalone_manager" "$behavior_test" "${project_root}/tools/fix-console-autologin.sh"
else
  printf 'ShellCheck not installed; skipping it.\n'
fi

printf 'All static checks passed.\n'
