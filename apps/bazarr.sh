write_bazarr_service() {
  cat > /etc/systemd/system/bazarr.service <<'EOF_SERVICE'
# ARRSUITE_TEMPLATE systemd/bazarr.service
EOF_SERVICE
}

configure_bazarr() {
  local app_dir="${1:-/opt/bazarr}"
  install -d -m 0775 /var/lib/bazarr
  chmod 0775 "$app_dir"
  sed -i.bak 's/--only-binary=Pillow//g' "${app_dir}/requirements.txt"
  $STD uv venv --clear "${app_dir}/venv" --python 3.12 || return
  $STD uv pip install -r "${app_dir}/requirements.txt" --python "${app_dir}/venv/bin/python3" || return
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
  local stage_dir=/opt/bazarr.arrsuite-new previous_dir=/opt/bazarr.arrsuite-previous stage_home=/opt/bazarr.arrsuite-home
  if check_for_gh_release "bazarr" "morpheus65535/bazarr"; then
    rm -rf "$stage_dir" "$stage_home"
    install -d -m 0700 "$stage_home"
    PYTHON_VERSION="3.12" setup_uv || return
    HOME="$stage_home" fetch_and_deploy_gh_release bazarr morpheus65535/bazarr prebuild latest "$stage_dir" bazarr.zip \
      || { rm -rf "$stage_dir" "$stage_home"; return 1; }
    configure_bazarr "$stage_dir" || { rm -rf "$stage_dir" "$stage_home"; return 1; }
    systemctl stop bazarr || { rm -rf "$stage_dir" "$stage_home"; return 1; }
    rm -rf "$previous_dir"
    mv /opt/bazarr "$previous_dir" || return
    mv "$stage_dir" /opt/bazarr || { mv "$previous_dir" /opt/bazarr; systemctl start bazarr || true; return 1; }
    if ! systemctl start bazarr || ! systemctl is-active --quiet bazarr; then
      systemctl stop bazarr || true; rm -rf /opt/bazarr; mv "$previous_dir" /opt/bazarr; systemctl start bazarr || true
      rm -rf "$stage_home"; return 1
    fi
    [[ -f "$stage_home/.bazarr" ]] && install -m 0644 "$stage_home/.bazarr" "$HOME/.bazarr"
    rm -rf "$previous_dir" "$stage_home"
    msg_ok "Updated Bazarr"
  fi
}
