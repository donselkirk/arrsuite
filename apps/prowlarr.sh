write_prowlarr_service() {
  cat > /etc/systemd/system/prowlarr.service <<'EOF_SERVICE'
[Unit]
Description=Prowlarr Daemon
After=syslog.target network.target

[Service]
UMask=0002
Type=simple
ExecStart=/opt/Prowlarr/Prowlarr -nobrowser -data=/var/lib/prowlarr/
TimeoutStopSec=20
KillMode=process
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF_SERVICE
}

install_prowlarr() {
  if [[ "$(dpkg --print-architecture)" != "amd64" ]]; then
    msg_error "Prowlarr is only supported on amd64 by the current Community Script."
    return 1
  fi

  msg_info "Installing Prowlarr Dependencies"
  $STD apt install -y sqlite3 || return
  msg_ok "Installed Prowlarr Dependencies"

  fetch_and_deploy_gh_release \
    "prowlarr" \
    "Prowlarr/Prowlarr" \
    "prebuild" \
    "latest" \
    "/opt/Prowlarr" \
    "Prowlarr.master*linux-core-x64.tar.gz" || return

  mkdir -p /var/lib/prowlarr/
  chmod 775 /var/lib/prowlarr/ /opt/Prowlarr
  write_prowlarr_service
  systemctl daemon-reload
  systemctl enable -q --now prowlarr || return
  register_app prowlarr
  msg_ok "Installed Prowlarr"
}

update_prowlarr() {
  if check_for_gh_release "prowlarr" "Prowlarr/Prowlarr"; then
    msg_info "Stopping Prowlarr"
    systemctl stop prowlarr || return
    msg_ok "Stopped Prowlarr"

    rm -rf /opt/Prowlarr
    fetch_and_deploy_gh_release \
      "prowlarr" \
      "Prowlarr/Prowlarr" \
      "prebuild" \
      "latest" \
      "/opt/Prowlarr" \
      "Prowlarr.master*linux-core-x64.tar.gz" || return
    chmod 775 /opt/Prowlarr

    msg_info "Starting Prowlarr"
    systemctl start prowlarr || return
    msg_ok "Started Prowlarr"
    msg_ok "Updated Prowlarr"
  fi
}

