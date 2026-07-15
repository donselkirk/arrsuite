write_bazarr_service() {
  cat > /etc/systemd/system/bazarr.service <<'EOF_SERVICE'
[Unit]
Description=Bazarr Daemon
After=syslog.target network.target

[Service]
WorkingDirectory=/opt/bazarr/
UMask=0002
Restart=on-failure
RestartSec=5
Type=simple
ExecStart=/opt/bazarr/venv/bin/python3 /opt/bazarr/bazarr.py
KillSignal=SIGINT
TimeoutStopSec=20
SyslogIdentifier=bazarr

[Install]
WantedBy=multi-user.target
EOF_SERVICE
}

configure_bazarr() {
  install -d -m 0775 /var/lib/bazarr
  chmod 0775 /opt/bazarr
  sed -i.bak 's/--only-binary=Pillow//g' /opt/bazarr/requirements.txt
  $STD uv venv --clear /opt/bazarr/venv --python 3.12 || return
  $STD uv pip install -r /opt/bazarr/requirements.txt --python /opt/bazarr/venv/bin/python3 || return
}

install_bazarr() {
  msg_info "Installing Bazarr"
  PYTHON_VERSION="3.12" setup_uv || return
  fetch_and_deploy_gh_release \
    "bazarr" \
    "morpheus65535/bazarr" \
    "prebuild" \
    "latest" \
    "/opt/bazarr" \
    "bazarr.zip" || return
  configure_bazarr || return
  msg_ok "Installed Bazarr"

  write_bazarr_service
  systemctl daemon-reload
  systemctl enable -q --now bazarr || return
  register_app bazarr
  msg_ok "Started Bazarr"
}

update_bazarr() {
  if check_for_gh_release "bazarr" "morpheus65535/bazarr"; then
    msg_info "Stopping Bazarr"
    systemctl stop bazarr || return
    msg_ok "Stopped Bazarr"

    PYTHON_VERSION="3.12" setup_uv || return
    fetch_and_deploy_gh_release \
      "bazarr" \
      "morpheus65535/bazarr" \
      "prebuild" \
      "latest" \
      "/opt/bazarr" \
      "bazarr.zip" || return
    configure_bazarr || return

    msg_info "Starting Bazarr"
    systemctl start bazarr || return
    msg_ok "Started Bazarr"
    msg_ok "Updated Bazarr"
  fi
}

