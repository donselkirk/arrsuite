#!/usr/bin/env bash

# Show once per login shell even if profile.d is sourced more than once.
[[ "${ARRSUITE_MOTD_SHOWN:-0}" == "1" ]] && return 0
export ARRSUITE_MOTD_SHOWN=1

registry="/opt/arrsuite/installed.apps"
ip_address="$(hostname -I 2>/dev/null | awk '{print $1}')"
if [[ -z "$ip_address" ]]; then
  ip_address="$(ip -4 addr show scope global 2>/dev/null | awk '/inet / {sub(/\/.*/, "", $2); print $2; exit}')"
fi

printf '\n\033[1;92mArrSuite LXC Container\033[0m\n'
printf ' OS: %s\n' "$(. /etc/os-release && printf '%s %s' "$NAME" "$VERSION_ID")"
printf ' Hostname: %s\n' "$(hostname)"
printf ' IP Address: %s\n' "${ip_address:-unavailable}"
printf ' Repository: https://github.com/donselkirk/arrsuite\n'
printf '\n Installed Applications:\n'

installed_count=0
if [[ -r "$registry" ]]; then
  while IFS= read -r app; do
    case "$app" in
      sonarr) label="Sonarr"; port="8989" ;;
      radarr) label="Radarr"; port="7878" ;;
      lidarr) label="Lidarr"; port="8686" ;;
      prowlarr) label="Prowlarr"; port="9696" ;;
      byparr) label="Byparr"; port="8191" ;;
      *) continue ;;
    esac

    state="$(systemctl is-active "$app" 2>/dev/null || true)"
    [[ -n "$state" ]] || state="unknown"
    printf '  - %-7s http://%s:%s (%s)\n' "$label" "${ip_address:-localhost}" "$port" "$state"
    installed_count=$((installed_count + 1))
  done <"$registry"
fi

if ((installed_count == 0)); then
  printf '  - None; run: arrsuite add\n'
fi
printf '\n'

unset registry ip_address installed_count app label port state
