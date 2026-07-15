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

