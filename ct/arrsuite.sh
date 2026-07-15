#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Don Selkirk
# License: MIT | https://github.com/community-scripts/ProxmoxVED/raw/main/LICENSE
# Source: https://wiki.servarr.com/

if [[ -n "${ARRSUITE_BUILD_FUNC_PATH:-}" ]]; then
  # The repository bootstrap supplies a temporary copy of the current upstream
  # helper with only its application-installer URL redirected to this project.
  source "$ARRSUITE_BUILD_FUNC_PATH"
else
  source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/misc/build.func)
fi

APP="ArrSuite"
var_tags="${var_tags:-arr;media}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-4096}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_arm64="${var_arm64:-yes}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -x /usr/local/bin/arrsuite ]]; then
    msg_error "No ${APP} installation found!"
    exit
  fi

  /usr/local/bin/arrsuite update
  exit
}

start
build_container
description

msg_ok "Completed successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW}Manage applications inside the LXC with:${CL} ${BGN}arrsuite${CL}"
echo -e "${INFO}${YW}Add applications later with:${CL} ${BGN}arrsuite add${CL}"
echo -e "${INFO}${YW}Update all installed applications with:${CL} ${BGN}update${CL}"
echo -e "${INFO}${YW}Application ports:${CL} ${BGN}Sonarr 8989, Radarr 7878, Lidarr 8686, Byparr 8191${CL}"
