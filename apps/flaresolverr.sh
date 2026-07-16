write_flaresolverr_service() {
  cat > /etc/systemd/system/flaresolverr.service <<'EOF_SERVICE'
# ARRSUITE_TEMPLATE systemd/flaresolverr.service
EOF_SERVICE
}

install_flaresolverr() {
  if [[ "$(dpkg --print-architecture)" != "amd64" ]]; then
    msg_error "FlareSolverr is only supported on amd64 by the current Community Script."
    return 1
  fi

  msg_info "Installing FlareSolverr Dependencies"
  $STD apt-get install -y apt-transport-https xvfb || return
  msg_ok "Installed FlareSolverr Dependencies"

  msg_info "Installing Chrome"
  setup_deb822_repo \
    "google-chrome" \
    "https://dl.google.com/linux/linux_signing_key.pub" \
    "https://dl.google.com/linux/chrome/deb/" \
    "stable" || return
  $STD apt update || return
  $STD apt install -y google-chrome-stable || return
  rm -f /etc/apt/sources.list.d/google-chrome.list
  msg_ok "Installed Chrome"

  fetch_and_deploy_gh_release \
    "flaresolverr" \
    "FlareSolverr/FlareSolverr" \
    "prebuild" \
    "latest" \
    "/opt/flaresolverr" \
    "flaresolverr_linux_x64.tar.gz" || return

  write_flaresolverr_service
  systemctl daemon-reload
  systemctl enable -q --now flaresolverr || return
  register_app flaresolverr
  msg_ok "Installed FlareSolverr"
}

update_flaresolverr() {
  if check_for_gh_release "flaresolverr" "FlareSolverr/FlareSolverr"; then
    staged_prebuilt_update flaresolverr flaresolverr FlareSolverr/FlareSolverr \
      /opt/flaresolverr "flaresolverr_linux_x64.tar.gz" || return
    msg_ok "Updated FlareSolverr"
  fi
}
