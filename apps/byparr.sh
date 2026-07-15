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

