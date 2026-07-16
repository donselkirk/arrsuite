write_sonarr_service() {
  cat > /etc/systemd/system/sonarr.service <<'EOF_SERVICE'
# ARRSUITE_TEMPLATE systemd/sonarr.service
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
    staged_prebuilt_update sonarr Sonarr Sonarr/Sonarr /opt/Sonarr \
      "Sonarr.main.*.linux-$(arch_resolve "x64" "arm64").tar.gz" || return
    msg_ok "Updated Sonarr"
  fi
}
