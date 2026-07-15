#!/usr/bin/env bash
set -Eeuo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
template="${project_root}/src/arrsuite-manager.sh.in"
manager="${project_root}/tools/arrsuite-manager"
installer="${project_root}/install/arrsuite-install.sh"
motd="${project_root}/tools/arrsuite-motd.sh"
readonly -a modules=(sonarr radarr lidarr prowlarr byparr flaresolverr seerr bazarr)
check_only=0
[[ "${1:-}" == "--check" ]] && check_only=1

tmp_manager="$(mktemp)"
tmp_installer="$(mktemp)"
trap 'rm -f "$tmp_manager" "$tmp_installer"' EXIT

{
  while IFS= read -r line; do
    if [[ "$line" == "# ARRSUITE_APP_MODULES" ]]; then
      for app in "${modules[@]}"; do
        printf '# Generated from apps/%s.sh. Do not edit this block directly.\n' "$app"
        sed -e '${/^$/d;}' "${project_root}/apps/${app}.sh"
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

awk -v manager="$manager" -v motd="$motd" '
  function copy_file(path, line) {
    while ((getline line < path) > 0) print line
    close(path)
  }
  /^cat > \/usr\/local\/bin\/arrsuite <<'"'"'EOF_MANAGER'"'"'$/ {
    print
    copy_file(manager)
    skipping_manager=1
    next
  }
  skipping_manager && /^EOF_MANAGER$/ {
    skipping_manager=0
    print
    next
  }
  skipping_manager { next }
  /^  cat >\/etc\/profile\.d\/00_lxc-details\.sh <<'"'"'EOF_MOTD'"'"'$/ {
    print
    copy_file(motd)
    skipping_motd=1
    next
  }
  skipping_motd && /^EOF_MOTD$/ {
    skipping_motd=0
    print
    next
  }
  skipping_motd { next }
  { print }
' "$installer" >"$tmp_installer"

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
