write_lidarr_service() {
  cat > /etc/systemd/system/lidarr.service <<'EOF_SERVICE'
# ARRSUITE_TEMPLATE systemd/lidarr.service
EOF_SERVICE
}

install_lidarr() {
  msg_info "Installing Lidarr Dependencies"
  $STD apt install -y sqlite3 libchromaprint-tools libicu-dev mediainfo || return
  msg_ok "Installed Lidarr Dependencies"

  fetch_and_deploy_gh_release \
    "lidarr" \
    "Lidarr/Lidarr" \
    "prebuild" \
    "latest" \
    "/opt/Lidarr" \
    "Lidarr.master*linux-core-$(arch_resolve "x64" "arm64").tar.gz" || return

  mkdir -p /var/lib/lidarr/
  chmod 775 /var/lib/lidarr/ /opt/Lidarr
  write_lidarr_service
  systemctl daemon-reload
  systemctl enable -q --now lidarr || return
  register_app lidarr
  msg_ok "Installed Lidarr"
}

update_lidarr() {
  if check_for_gh_release "lidarr" "Lidarr/Lidarr"; then
    staged_prebuilt_update lidarr lidarr Lidarr/Lidarr /opt/Lidarr \
      "Lidarr.master*linux-core-$(arch_resolve "x64" "arm64").tar.gz" 0775 || return
    msg_ok "Updated Lidarr"
  fi
}
