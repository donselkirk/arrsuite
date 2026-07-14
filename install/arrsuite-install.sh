#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Don Selkirk
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://wiki.servarr.com/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

# Keep an ArrSuite-owned fallback for passwordless console access. The shared
# Community Scripts customize() helper normally performs this configuration,
# but configuring both getty paths here prevents regressions when the helper
# implementation or the Proxmox console path changes.
configure_arrsuite_console_autologin() {
  [[ -z "${PASSWORD:-}" ]] || return 0

  msg_info "Configuring Console Auto-Login"
  passwd -d root &>/dev/null || true

  if systemctl cat container-getty@.service &>/dev/null \
    || [[ -f /usr/lib/systemd/system/container-getty@.service ]] \
    || [[ -f /lib/systemd/system/container-getty@.service ]]; then
    install -d -m 0755 /etc/systemd/system/container-getty@1.service.d
    cat >/etc/systemd/system/container-getty@1.service.d/override.conf <<'EOF_GETTY'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear --noissue --keep-baud tty%I 115200,38400,9600 - $TERM
EOF_GETTY
  fi

  if systemctl cat console-getty.service &>/dev/null \
    || [[ -f /usr/lib/systemd/system/console-getty.service ]] \
    || [[ -f /lib/systemd/system/console-getty.service ]]; then
    install -d -m 0755 /etc/systemd/system/console-getty.service.d
    cat >/etc/systemd/system/console-getty.service.d/override.conf <<'EOF_CONSOLE'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear --noissue --keep-baud 115200,38400,9600 - $TERM
EOF_CONSOLE
    systemctl enable console-getty.service &>/dev/null || true
  fi

  systemctl daemon-reload
  systemctl try-restart container-getty@1.service &>/dev/null || true
  systemctl try-restart console-getty.service &>/dev/null || true
  msg_ok "Configured Console Auto-Login"
}

msg_info "Installing ArrSuite Manager Dependencies"
$STD apt install -y whiptail
msg_ok "Installed ArrSuite Manager Dependencies"

msg_info "Creating ArrSuite Manager"
install -d -m 0755 /opt/arrsuite/lib
install -d -m 0755 /opt/arrsuite
printf '%s\n' "$FUNCTIONS_FILE_PATH" >/opt/arrsuite/lib/community-functions.sh
chmod 0644 /opt/arrsuite/lib/community-functions.sh
touch /opt/arrsuite/installed.apps
chmod 0644 /opt/arrsuite/installed.apps

cat > /usr/local/bin/arrsuite <<'EOF_MANAGER'
#!/usr/bin/env bash
set -Euo pipefail

export APP="ArrSuite"
export NSAPP="arrsuite"
VERBOSE="${VERBOSE:-no}"
STD="${STD:-}"

readonly BASE_DIR="${ARRSUITE_BASE_DIR:-/opt/arrsuite}"
readonly REGISTRY="${ARRSUITE_REGISTRY:-${BASE_DIR}/installed.apps}"
readonly FUNCTIONS_LIBRARY="${ARRSUITE_FUNCTIONS_LIBRARY:-${BASE_DIR}/lib/community-functions.sh}"
readonly LOCK_FILE="${ARRSUITE_LOCK_FILE:-/run/lock/arrsuite.lock}"
readonly -a SUPPORTED_APPS=(sonarr radarr lidarr byparr)

declare -A APP_LABEL=(
  [sonarr]="Sonarr"
  [radarr]="Radarr"
  [lidarr]="Lidarr"
  [byparr]="Byparr"
)

declare -A APP_DESCRIPTION=(
  [sonarr]="TV series manager (port 8989)"
  [radarr]="Movie manager (port 7878)"
  [lidarr]="Music collection manager (port 8686)"
  [byparr]="Cloudflare bypass service (port 8191; amd64 only)"
)

declare -A APP_PORT=(
  [sonarr]="8989"
  [radarr]="7878"
  [lidarr]="8686"
  [byparr]="8191"
)

[[ $EUID -eq 0 || "${ARRSUITE_ALLOW_NON_ROOT:-0}" == "1" ]] || {
  echo "Run arrsuite as root." >&2
  exit 1
}

[[ -r "$FUNCTIONS_LIBRARY" ]] || {
  echo "Missing Community Scripts function library: ${FUNCTIONS_LIBRARY}" >&2
  exit 1
}

# Persist the same Community Scripts helper bundle used by the original
# Sonarr, Radarr, Lidarr, and Byparr installers. This lets future `arrsuite add` and
# `arrsuite update` operations reuse fetch_and_deploy_gh_release,
# check_for_gh_release, setup_uv, arch_resolve, and the standard UI functions.
source "$FUNCTIONS_LIBRARY"
color

install -d -m 0755 "$BASE_DIR" "$(dirname "$LOCK_FILE")"
touch "$REGISTRY"

normalize_app() {
  printf '%s' "${1,,}" | tr -cd 'a-z0-9_-'
}

is_supported() {
  local requested app
  requested="$(normalize_app "$1")"
  for app in "${SUPPORTED_APPS[@]}"; do
    [[ "$app" == "$requested" ]] && return 0
  done
  return 1
}

is_installed() {
  local app
  app="$(normalize_app "$1")"
  grep -Fxq "$app" "$REGISTRY" 2>/dev/null
}

register_app() {
  local app
  app="$(normalize_app "$1")"
  if ! is_installed "$app"; then
    printf '%s\n' "$app" >>"$REGISTRY"
    sort -u -o "$REGISTRY" "$REGISTRY"
  fi
}

acquire_lock() {
  exec 9>"$LOCK_FILE"
  flock -n 9 || {
    msg_error "Another ArrSuite operation is already running."
    exit 1
  }
}

write_sonarr_service() {
  cat > /etc/systemd/system/sonarr.service <<'EOF_SERVICE'
[Unit]
Description=Sonarr Daemon
After=syslog.target network.target

[Service]
Type=simple
ExecStart=/opt/Sonarr/Sonarr -nobrowser -data=/var/lib/sonarr/
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF_SERVICE
}

write_radarr_service() {
  cat > /etc/systemd/system/radarr.service <<'EOF_SERVICE'
[Unit]
Description=Radarr Daemon
After=syslog.target network.target

[Service]
UMask=0002
Type=simple
ExecStart=/opt/Radarr/Radarr -nobrowser -data=/var/lib/radarr/
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF_SERVICE
}

write_lidarr_service() {
  cat > /etc/systemd/system/lidarr.service <<'EOF_SERVICE'
[Unit]
Description=Lidarr Daemon
After=syslog.target network.target

[Service]
UMask=0002
Type=simple
ExecStart=/opt/Lidarr/Lidarr -nobrowser -data=/var/lib/lidarr/
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF_SERVICE
}

write_byparr_service() {
  cat > /etc/systemd/system/byparr.service <<'EOF_SERVICE'
[Unit]
Description=Byparr
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/Byparr
ExecStart=/usr/local/bin/uv run python3 main.py
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF_SERVICE
}

install_byparr_dependencies() {
  msg_info "Installing Byparr Dependencies"
  $STD apt install -y --no-install-recommends \
    ffmpeg \
    libatk1.0-0 \
    libcairo-gobject2 \
    libcairo2 \
    libdbus-glib-1-2 \
    libfontconfig1 \
    libfreetype6 \
    libgdk-pixbuf-xlib-2.0-0 \
    libglib2.0-0 \
    libgtk-3-0 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libpangoft2-1.0-0 \
    libx11-6 \
    libx11-xcb1 \
    libxcb-shm0 \
    libxcb1 \
    libxcomposite1 \
    libxcursor1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxi6 \
    libxrender1 \
    libxt6 \
    libxtst6 \
    xvfb \
    fonts-noto-color-emoji \
    fonts-unifont \
    xfonts-cyrillic \
    xfonts-scalable \
    fonts-liberation \
    fonts-ipafont-gothic \
    fonts-wqy-zenhei \
    fonts-tlwg-loma-otf || return
  $STD apt autoremove -y chromium
  msg_ok "Installed Byparr Dependencies"
}

install_sonarr() {
  msg_info "Installing Sonarr Dependencies"
  $STD apt install -y sqlite3 libicu-dev || return
  msg_ok "Installed Sonarr Dependencies"

  fetch_and_deploy_gh_release \
    "Sonarr" \
    "Sonarr/Sonarr" \
    "prebuild" \
    "latest" \
    "/opt/Sonarr" \
    "Sonarr.main.*.linux-$(arch_resolve "x64" "arm64").tar.gz" || return

  mkdir -p /var/lib/sonarr/
  chmod 775 /var/lib/sonarr/
  write_sonarr_service
  systemctl daemon-reload
  systemctl enable -q --now sonarr || return
  register_app sonarr
  msg_ok "Installed Sonarr"
}

update_sonarr() {
  if check_for_gh_release "Sonarr" "Sonarr/Sonarr"; then
    msg_info "Stopping Sonarr"
    systemctl stop sonarr || return
    msg_ok "Stopped Sonarr"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release \
      "Sonarr" \
      "Sonarr/Sonarr" \
      "prebuild" \
      "latest" \
      "/opt/Sonarr" \
      "Sonarr.main.*.linux-$(arch_resolve "x64" "arm64").tar.gz" || return

    msg_info "Starting Sonarr"
    systemctl start sonarr || return
    msg_ok "Started Sonarr"
    msg_ok "Updated Sonarr"
  fi
}

install_radarr() {
  msg_info "Installing Radarr Dependencies"
  $STD apt install -y sqlite3 libicu-dev || return
  msg_ok "Installed Radarr Dependencies"

  fetch_and_deploy_gh_release \
    "Radarr" \
    "Radarr/Radarr" \
    "prebuild" \
    "latest" \
    "/opt/Radarr" \
    "Radarr.master*linux-core-$(arch_resolve "x64" "arm64").tar.gz" || return

  mkdir -p /var/lib/radarr/
  chmod 775 /var/lib/radarr/ /opt/Radarr
  write_radarr_service
  systemctl daemon-reload
  systemctl enable -q --now radarr || return
  register_app radarr
  msg_ok "Installed Radarr"
}

update_radarr() {
  if check_for_gh_release "Radarr" "Radarr/Radarr"; then
    msg_info "Stopping Radarr"
    systemctl stop radarr || return
    msg_ok "Stopped Radarr"

    rm -rf /opt/Radarr
    fetch_and_deploy_gh_release \
      "Radarr" \
      "Radarr/Radarr" \
      "prebuild" \
      "latest" \
      "/opt/Radarr" \
      "Radarr.master*linux-core-$(arch_resolve "x64" "arm64").tar.gz" || return
    chmod 775 /opt/Radarr

    msg_info "Starting Radarr"
    systemctl start radarr || return
    msg_ok "Started Radarr"
    msg_ok "Updated Radarr"
  fi
}

install_lidarr() {
  msg_info "Installing Lidarr Dependencies"
  $STD apt install -y sqlite3 libchromaprint-tools libicu-dev mediainfo || return
  msg_ok "Installed Lidarr Dependencies"

  fetch_and_deploy_gh_release \
    "lidarr" \
    "Lidarr/Lidarr" \
    "prebuild" \
    "latest" \
    "/opt/Lidarr" \
    "Lidarr.master*linux-core-$(arch_resolve "x64" "arm64").tar.gz" || return

  mkdir -p /var/lib/lidarr/
  chmod 775 /var/lib/lidarr/ /opt/Lidarr
  write_lidarr_service
  systemctl daemon-reload
  systemctl enable -q --now lidarr || return
  register_app lidarr
  msg_ok "Installed Lidarr"
}

update_lidarr() {
  if check_for_gh_release "lidarr" "Lidarr/Lidarr"; then
    msg_info "Stopping Lidarr"
    systemctl stop lidarr || return
    msg_ok "Stopped Lidarr"

    fetch_and_deploy_gh_release \
      "lidarr" \
      "Lidarr/Lidarr" \
      "prebuild" \
      "latest" \
      "/opt/Lidarr" \
      "Lidarr.master*linux-core-$(arch_resolve "x64" "arm64").tar.gz" || return
    chmod 775 /opt/Lidarr

    msg_info "Starting Lidarr"
    systemctl start lidarr || return
    msg_ok "Started Lidarr"
    msg_ok "Updated Lidarr"
  fi
}

install_byparr() {
  if [[ "$(dpkg --print-architecture)" != "amd64" ]]; then
    msg_error "Byparr is only supported on amd64 by the current Community Script."
    return 1
  fi

  install_byparr_dependencies || return
  setup_uv || return
  fetch_and_deploy_gh_release "Byparr" "ThePhaseless/Byparr" "tarball" "latest" || return

  msg_info "Configuring Byparr"
  cd /opt/Byparr
  $STD uv sync --link-mode copy || return
  $STD uv run camoufox fetch || return
  msg_ok "Configured Byparr"

  write_byparr_service
  systemctl daemon-reload
  systemctl enable -q --now byparr || return
  register_app byparr
  msg_ok "Installed Byparr"
}

update_byparr() {
  if check_for_gh_release "Byparr" "ThePhaseless/Byparr"; then
    msg_info "Stopping Byparr"
    systemctl stop byparr || return
    msg_ok "Stopped Byparr"

    CLEAN_INSTALL=1 fetch_and_deploy_gh_release \
      "Byparr" \
      "ThePhaseless/Byparr" \
      "tarball" \
      "latest" || return

    if ! dpkg -l | grep -q ffmpeg; then
      install_byparr_dependencies || return
    fi

    setup_uv || return
    msg_info "Configuring Byparr"
    cd /opt/Byparr
    $STD uv sync --link-mode copy || return
    $STD uv run camoufox fetch || return
    msg_ok "Configured Byparr"

    msg_info "Starting Byparr"
    systemctl start byparr || return
    msg_ok "Started Byparr"
    msg_ok "Updated Byparr"
  fi
}

install_app() {
  local app
  app="$(normalize_app "$1")"

  case "$app" in
    sonarr) install_sonarr ;;
    radarr) install_radarr ;;
    lidarr) install_lidarr ;;
    byparr) install_byparr ;;
    *)
      msg_error "Unsupported application: $1"
      return 1
      ;;
  esac
}

update_app() {
  local app
  app="$(normalize_app "$1")"

  case "$app" in
    sonarr) update_sonarr ;;
    radarr) update_radarr ;;
    lidarr) update_lidarr ;;
    byparr) update_byparr ;;
    *)
      msg_error "Unsupported application: $1"
      return 1
      ;;
  esac
}

choose_uninstalled_apps() {
  local -a options=()
  local app selection default_state

  for app in "${SUPPORTED_APPS[@]}"; do
    if ! is_installed "$app"; then
      default_state="ON"
      [[ "$app" == "lidarr" || "$app" == "byparr" ]] && default_state="OFF"
      options+=("$app" "${APP_DESCRIPTION[$app]}" "$default_state")
    fi
  done

  if ((${#options[@]} == 0)); then
    msg_ok "Every supported application is already installed" >&2
    return 0
  fi

  if [[ -r /dev/tty && -w /dev/tty ]] && command -v whiptail >/dev/null 2>&1; then
    selection="$(whiptail \
      --title "ArrSuite Application Selection" \
      --checklist "Choose applications to install. Space toggles; Enter confirms." \
      18 78 8 \
      "${options[@]}" \
      --separate-output \
      3>&1 1>/dev/tty 2>&3 </dev/tty)" || return 130
    printf '%s\n' "$selection"
    return 0
  fi

  msg_warn "No interactive terminal detected; selecting Sonarr and Radarr by default" >&2
  for app in sonarr radarr; do
    is_installed "$app" || printf '%s\n' "$app"
  done
}

add_apps() {
  local -a apps=("$@")
  local app failures=0

  if ((${#apps[@]} == 0)); then
    mapfile -t apps < <(choose_uninstalled_apps)
  fi

  if ((${#apps[@]} == 0)); then
    msg_ok "No applications selected"
    return 0
  fi

  for app in "${apps[@]}"; do
    app="$(normalize_app "$app")"
    [[ -n "$app" ]] || continue

    if ! is_supported "$app"; then
      msg_error "Unsupported application: $app"
      failures=$((failures + 1))
      continue
    fi

    if is_installed "$app"; then
      msg_ok "${APP_LABEL[$app]} is already installed"
      continue
    fi

    if (set -e; install_app "$app"); then
      :
    else
      msg_error "Failed to install ${APP_LABEL[$app]}"
      failures=$((failures + 1))
    fi
  done

  ((failures == 0))
}

update_apps() {
  local -a apps=("$@")
  local app failures=0

  if ((${#apps[@]} == 0)); then
    mapfile -t apps <"$REGISTRY"
  fi

  if ((${#apps[@]} == 0)); then
    msg_warn "No applications are installed. Run: arrsuite add"
    return 0
  fi

  for app in "${apps[@]}"; do
    app="$(normalize_app "$app")"
    [[ -n "$app" ]] || continue

    if ! is_installed "$app"; then
      msg_error "${app} is not installed. Run: arrsuite add ${app}"
      failures=$((failures + 1))
      continue
    fi

    if (set -e; update_app "$app"); then
      :
    else
      msg_error "Failed to update ${APP_LABEL[$app]:-$app}"
      failures=$((failures + 1))
    fi
  done

  if ((failures > 0)); then
    msg_error "${failures} application operation(s) failed; remaining apps were still processed"
    return 1
  fi

  msg_ok "All installed ArrSuite applications are current"
}

show_list() {
  local app installed service_state
  printf '%-10s %-11s %-10s %-12s\n' "APP" "INSTALLED" "PORT" "SERVICE"
  printf '%-10s %-11s %-10s %-12s\n' "----------" "-----------" "----------" "------------"

  for app in "${SUPPORTED_APPS[@]}"; do
    installed="no"
    service_state="-"
    if is_installed "$app"; then
      installed="yes"
      service_state="$(systemctl is-active "$app" 2>/dev/null || true)"
    fi
    printf '%-10s %-11s %-10s %-12s\n' \
      "${APP_LABEL[$app]}" \
      "$installed" \
      "${APP_PORT[$app]}" \
      "$service_state"
  done
}

show_status() {
  local app
  if [[ ! -s "$REGISTRY" ]]; then
    msg_warn "No applications are installed"
    return 0
  fi

  while IFS= read -r app; do
    [[ -n "$app" ]] || continue
    echo
    systemctl --no-pager --full status "$app" || true
  done <"$REGISTRY"
}

show_help() {
  cat <<'EOF_HELP'
ArrSuite multi-application manager

Usage:
  arrsuite add [app ...]       Install apps; opens a checklist when no app is named
  arrsuite update [app ...]    Update all installed apps, or only named apps
  arrsuite list                Show supported apps, ports, and service state
  arrsuite status              Show systemd status for installed apps
  arrsuite help                Show this help

Supported apps:
  sonarr    TV series manager, port 8989
  radarr    Movie manager, port 7878
  lidarr    Music collection manager, port 8686
  byparr    Cloudflare bypass service, port 8191 (amd64 only)

The Community Scripts command `update` invokes `arrsuite update`.
EOF_HELP
}

main() {
  case "${1:-help}" in
    add|install)
      acquire_lock
      shift
      add_apps "$@"
      ;;
    update|upgrade)
      acquire_lock
      shift
      update_apps "$@"
      ;;
    list)
      show_list
      ;;
    status)
      show_status
      ;;
    help|-h|--help)
      show_help
      ;;
    *)
      show_help >&2
      exit 2
      ;;
  esac
}

main "$@"
EOF_MANAGER

chmod 0755 /usr/local/bin/arrsuite
msg_ok "Created ArrSuite Manager"

msg_info "Selecting ArrSuite Applications"
if [[ -n "${ARRSUITE_APPS:-}" ]]; then
  read -r -a selected_apps <<<"${ARRSUITE_APPS//,/ }"
  /usr/local/bin/arrsuite add "${selected_apps[@]}"
else
  /usr/local/bin/arrsuite add
fi
msg_ok "Installed Selected ArrSuite Applications"

motd_ssh
customize
configure_arrsuite_console_autologin

# The shared customize() helper creates the standard remote update wrapper.
# Until ArrSuite is merged upstream, keep the prototype self-contained and
# make `update` call the local multi-app manager directly.
cat >/usr/bin/update <<'EOF_UPDATE'
#!/usr/bin/env bash
exec /usr/local/bin/arrsuite update "$@"
EOF_UPDATE
chmod 0755 /usr/bin/update

cleanup_lxc
