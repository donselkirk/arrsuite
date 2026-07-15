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
    staged_prebuilt_update radarr Radarr Radarr/Radarr /opt/Radarr \
      "Radarr.master*linux-core-$(arch_resolve "x64" "arm64").tar.gz" 0775 || return
    msg_ok "Updated Radarr"
  fi
}
