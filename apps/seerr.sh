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
  local app_dir="${1:-/opt/seerr}" pnpm_desired
  pnpm_desired="$(grep -Po '"pnpm":\s*"\K[^"]+' "${app_dir}/package.json")" || return
  [[ -n "$pnpm_desired" ]] || return 1
  NODE_VERSION="22" NODE_MODULE="pnpm@${pnpm_desired}" setup_nodejs || return
  export CYPRESS_INSTALL_BINARY=0
  export NODE_OPTIONS="--max-old-space-size=3072"
  cd "$app_dir"
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
  local stage_dir=/opt/seerr.arrsuite-new previous_dir=/opt/seerr.arrsuite-previous stage_home=/opt/seerr.arrsuite-home
  if check_for_gh_release "seerr" "seerr-team/seerr"; then
    rm -rf "$stage_dir" "$stage_home"
    install -d -m 0700 "$stage_home"
    HOME="$stage_home" fetch_and_deploy_gh_release "seerr" "seerr-team/seerr" "tarball" "latest" "$stage_dir" \
      || { rm -rf "$stage_dir" "$stage_home"; return 1; }
    build_seerr "$stage_dir" || { rm -rf "$stage_dir" "$stage_home"; return 1; }
    systemctl stop seerr || { rm -rf "$stage_dir" "$stage_home"; return 1; }
    rm -rf "$previous_dir"
    mv /opt/seerr "$previous_dir" || { rm -rf "$stage_dir"; systemctl start seerr || true; return 1; }
    if [[ -d "$previous_dir/config" ]] && ! mv "$previous_dir/config" "$stage_dir/config"; then
      mv "$previous_dir" /opt/seerr
      systemctl start seerr || true
      rm -rf "$stage_dir" "$stage_home"
      return 1
    fi
    if ! mv "$stage_dir" /opt/seerr; then
      if [[ -d "$stage_dir/config" && ! -d "$previous_dir/config" ]]; then
        mv "$stage_dir/config" "$previous_dir/config" || true
      fi
      rm -rf /opt/seerr
      mv "$previous_dir" /opt/seerr
      systemctl start seerr || true
      rm -rf "$stage_dir" "$stage_home"
      return 1
    fi
    if ! systemctl start seerr || ! systemctl is-active --quiet seerr; then
      systemctl stop seerr || true
      [[ -d /opt/seerr/config ]] && mv /opt/seerr/config "$previous_dir/config"
      rm -rf /opt/seerr
      mv "$previous_dir" /opt/seerr
      systemctl start seerr || true
      rm -rf "$stage_home"
      return 1
    fi
    [[ -f "$stage_home/.seerr" ]] && install -m 0644 "$stage_home/.seerr" "$HOME/.seerr"
    rm -rf "$stage_home"
    rm -rf "$previous_dir"
    msg_ok "Updated Seerr"
  fi
}
