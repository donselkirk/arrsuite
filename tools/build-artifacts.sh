#!/usr/bin/env bash
set -Eeuo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
template="${project_root}/src/arrsuite-manager.sh.in"
installer_template="${project_root}/src/arrsuite-install.sh.in"
manager="${project_root}/tools/arrsuite-manager"
installer="${project_root}/install/arrsuite-install.sh"
motd="${project_root}/tools/arrsuite-motd.sh"
templates="${project_root}/templates"
readonly -a modules=(sonarr radarr lidarr prowlarr byparr flaresolverr seerr bazarr)
check_only=0
[[ "${1:-}" == "--check" ]] && check_only=1

tmp_manager="$(mktemp)"
tmp_installer="$(mktemp)"
trap 'rm -f "$tmp_manager" "$tmp_installer"' EXIT

render_template_markers() {
  local source="$1" line relative
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^([[:space:]]*)#[[:space:]]ARRSUITE_TEMPLATE[[:space:]](.+)$ ]]; then
      relative="${BASH_REMATCH[2]}"
      [[ -f "${templates}/${relative}" ]] || {
        echo "Missing template: templates/${relative}" >&2
        return 1
      }
      sed "s/^/${BASH_REMATCH[1]}/" "${templates}/${relative}"
    else
      printf '%s\n' "$line"
    fi
  done <"$source"
}

{
  while IFS= read -r line; do
    if [[ "$line" == "# ARRSUITE_APP_MODULES" ]]; then
      for app in "${modules[@]}"; do
        printf '# Generated from apps/%s.sh. Do not edit this block directly.\n' "$app"
        render_template_markers "${project_root}/apps/${app}.sh" | sed -e '${/^$/d;}'
        printf '\n'
      done
    else
      printf '%s\n' "$line"
    fi
  done <"$template"
} >"$tmp_manager"

bash -n "$tmp_manager"
if ((check_only)); then
  cmp -s "$tmp_manager" "$manager" || {
    echo "tools/arrsuite-manager is stale; run: bash tools/build-artifacts.sh" >&2
    exit 1
  }
else
  install -m 0755 "$tmp_manager" "$manager"
fi

while IFS= read -r line || [[ -n "$line" ]]; do
  case "$line" in
    "# ARRSUITE_INSTALL_MANAGER") cat "$manager" ;;
    "# ARRSUITE_INSTALL_MOTD") cat "$motd" ;;
    "# ARRSUITE_INSTALL_CONTAINER_GETTY")
      cat "${templates}/getty/container-getty.override.conf"
      ;;
    "# ARRSUITE_INSTALL_CONSOLE_GETTY")
      cat "${templates}/getty/console-getty.override.conf"
      ;;
    "# ARRSUITE_INSTALL_UPDATE") cat "${templates}/update.sh" ;;
    *) printf '%s\n' "$line" ;;
  esac
done <"$installer_template" >"$tmp_installer"

bash -n "$tmp_installer"
if ((check_only)); then
  cmp -s "$tmp_installer" "$installer" || {
    echo "install/arrsuite-install.sh is stale; run: bash tools/build-artifacts.sh" >&2
    exit 1
  }
  printf 'Generated artifacts are current.\n'
else
  install -m 0644 "$tmp_installer" "$installer"
  printf 'Generated tools/arrsuite-manager and install/arrsuite-install.sh\n'
fi
