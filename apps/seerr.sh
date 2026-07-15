write_seerr_service() {
  install -d -m 0755 /etc/seerr
  cat > /etc/seerr/seerr.conf <<'EOF_CONFIG'
PORT=5055
HOST=0.0.0.0
EOF_CONFIG
  cat > /etc/systemd/system/seerr.service <<'EOF_SERVICE'
[Unit]
Description=Seerr Service
Wants=network-online.target
After=network-online.target

[Service]
EnvironmentFile=/etc/seerr/seerr.conf
Environment=NODE_ENV=production
Type=exec
Restart=on-failure
WorkingDirectory=/opt/seerr
ExecStart=/usr/bin/node dist/index.js

[Install]
WantedBy=multi-user.target
EOF_SERVICE
}

build_seerr() {
  local pnpm_desired
  pnpm_desired="$(grep -Po '"pnpm":\s*"\K[^"]+' /opt/seerr/package.json)" || return
  [[ -n "$pnpm_desired" ]] || return 1
  NODE_VERSION="22" NODE_MODULE="pnpm@${pnpm_desired}" setup_nodejs || return
  export CYPRESS_INSTALL_BINARY=0
  export NODE_OPTIONS="--max-old-space-size=3072"
  cd /opt/seerr
  $STD pnpm install --frozen-lockfile || return
  $STD pnpm build || return
}

install_seerr() {
  msg_info "Installing Seerr Dependencies"
  $STD apt install -y build-essential python3-setuptools || return
  msg_ok "Installed Seerr Dependencies"

  fetch_and_deploy_gh_release "seerr" "seerr-team/seerr" "tarball" "latest" || return
  build_seerr || return
  write_seerr_service
  systemctl daemon-reload
  systemctl enable -q --now seerr || return
  register_app seerr
  msg_ok "Installed Seerr"
}

update_seerr() {
  local config_backup=""
  if check_for_gh_release "seerr" "seerr-team/seerr"; then
    msg_info "Stopping Seerr"
    systemctl stop seerr || return
    msg_ok "Stopped Seerr"

    if [[ -d /opt/seerr/config ]]; then
      config_backup="$(mktemp -d)/config"
      mv /opt/seerr/config "$config_backup" || return
    fi
    rm -rf /opt/seerr
    if ! fetch_and_deploy_gh_release "seerr" "seerr-team/seerr" "tarball" "latest"; then
      if [[ -n "$config_backup" ]]; then
        install -d /opt/seerr
        mv "$config_backup" /opt/seerr/config
      fi
      return 1
    fi
    if [[ -n "$config_backup" ]]; then
      mv "$config_backup" /opt/seerr/config || return
    fi
    build_seerr || return

    msg_info "Starting Seerr"
    systemctl start seerr || return
    msg_ok "Started Seerr"
    msg_ok "Updated Seerr"
  fi
}

