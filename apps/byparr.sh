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
  local stage_dir=/opt/Byparr.arrsuite-new previous_dir=/opt/Byparr.arrsuite-previous stage_home=/opt/Byparr.arrsuite-home
  if check_for_gh_release "Byparr" "ThePhaseless/Byparr"; then
    if ! dpkg -l | grep -q ffmpeg; then
      install_byparr_dependencies || return
    fi
    setup_uv || return
    rm -rf "$stage_dir" "$stage_home"
    install -d -m 0700 "$stage_home"
    HOME="$stage_home" fetch_and_deploy_gh_release Byparr ThePhaseless/Byparr tarball latest "$stage_dir" \
      || { rm -rf "$stage_dir" "$stage_home"; return 1; }
    cd "$stage_dir"
    $STD uv sync --link-mode copy || return
    $STD uv run camoufox fetch || return
    systemctl stop byparr || { rm -rf "$stage_dir" "$stage_home"; return 1; }
    rm -rf "$previous_dir"
    mv /opt/Byparr "$previous_dir" || return
    mv "$stage_dir" /opt/Byparr || { mv "$previous_dir" /opt/Byparr; systemctl start byparr || true; return 1; }
    if ! systemctl start byparr || ! systemctl is-active --quiet byparr; then
      systemctl stop byparr || true; rm -rf /opt/Byparr; mv "$previous_dir" /opt/Byparr; systemctl start byparr || true
      rm -rf "$stage_home"; return 1
    fi
    [[ -f "$stage_home/.byparr" ]] && install -m 0644 "$stage_home/.byparr" "$HOME/.byparr"
    rm -rf "$previous_dir" "$stage_home"
    msg_ok "Updated Byparr"
  fi
}
