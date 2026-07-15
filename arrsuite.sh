#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPOSITORY_RAW_URL="${ARRSUITE_REPOSITORY_RAW_URL:-https://raw.githubusercontent.com/donselkirk/arrsuite/main}"
readonly COMMUNITY_RAW_URL="${COMMUNITY_SCRIPTS_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main}"

bootstrap_dir="$(mktemp -d)"
trap 'rm -rf "$bootstrap_dir"' EXIT

build_func="${bootstrap_dir}/build.func"
curl -fsSL "${COMMUNITY_RAW_URL}/misc/build.func" -o "$build_func"

# Keep the live Community Scripts framework and its helper URLs intact. Only
# redirect the two locations that fetch the application-specific installer
# (the normal path and the APT-recovery retry path).
# shellcheck disable=SC2016 # Match literal variable references in build.func.
sed -i \
  -e 's|"$COMMUNITY_SCRIPTS_URL/install/${var_install}.sh"|"$ARRSUITE_INSTALL_URL"|g' \
  -e 's|"https://raw.githubusercontent.com/community-scripts/ProxmoxVED/main/install/${var_install}.sh"|"$ARRSUITE_INSTALL_URL"|g' \
  "$build_func"

# shellcheck disable=SC2016 # Verify the literal reference inserted above.
redirect_count="$(grep -c 'curl -fsSL "$ARRSUITE_INSTALL_URL"' "$build_func" || true)"
if [[ "$redirect_count" -lt 2 ]]; then
  echo "Unable to redirect the Community Scripts installer URLs; upstream build.func may have changed." >&2
  exit 1
fi

export ARRSUITE_BUILD_FUNC_PATH="$build_func"
export ARRSUITE_INSTALL_URL="${REPOSITORY_RAW_URL}/install/arrsuite-install.sh"

source <(curl -fsSL "${REPOSITORY_RAW_URL}/ct/arrsuite.sh")
