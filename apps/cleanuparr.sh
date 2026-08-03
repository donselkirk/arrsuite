write_cleanuparr_service() {
  cat > /etc/systemd/system/cleanuparr.service <<'EOF_SERVICE'
# ARRSUITE_TEMPLATE systemd/cleanuparr.service
EOF_SERVICE
}

create_cleanuparr_pre_update_backup() {
  local destination="${BASE_DIR}/backups/pre-update/cleanuparr" timestamp archive was_active=0
  [[ -d "$CLEANUPARR_CONFIG_PATH" ]] || { msg_error "Cleanuparr configuration not found: $CLEANUPARR_CONFIG_PATH"; return 1; }
  install -d -m 0750 "$destination"
  timestamp="$(date +%Y.%m.%d_%H.%M.%S)"
  archive="${destination}/cleanuparr_config_${timestamp}.tar.gz"
  systemctl is-active --quiet cleanuparr && was_active=1
  ((was_active == 0)) || systemctl stop cleanuparr || return
  if ! tar -czf "$archive" -C "$(dirname "$CLEANUPARR_CONFIG_PATH")" "$(basename "$CLEANUPARR_CONFIG_PATH")"; then
    rm -f "$archive"
    ((was_active == 0)) || systemctl start cleanuparr || true
    return 1
  fi
  ((was_active == 0)) || systemctl start cleanuparr || return
  msg_ok "Created Cleanuparr backup: ${archive}"
}

install_cleanuparr() {
  msg_info "Installing Cleanuparr"
  fetch_and_deploy_gh_release "Cleanuparr" "Cleanuparr/Cleanuparr" "prebuild" "latest" \
    "/opt/cleanuparr" "*linux-$(arch_resolve).zip" || return
  install -d -m 0755 "$CLEANUPARR_CONFIG_PATH" "$CLEANUPARR_LOG_PATH"
  write_cleanuparr_service
  systemctl daemon-reload
  systemctl enable -q --now cleanuparr || return
  register_app cleanuparr
  msg_ok "Installed Cleanuparr"
}

update_cleanuparr() {
  if check_for_gh_release "cleanuparr" "Cleanuparr/Cleanuparr"; then
    create_cleanuparr_pre_update_backup || return
    staged_prebuilt_update cleanuparr Cleanuparr Cleanuparr/Cleanuparr /opt/cleanuparr \
      "*linux-$(arch_resolve).zip" || return
    msg_ok "Updated Cleanuparr"
  fi
}
