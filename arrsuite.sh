#!/usr/bin/env bash
# Community Scripts helpers reference several optional environment variables
# directly. Explicitly disable inherited nounset before loading any helpers.
set +u
set -Eeo pipefail

readonly DEFAULT_COMMUNITY_RAW_URL="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main"
readonly DEFAULT_RELEASE_BASE_URL="https://github.com/donselkirk/arrsuite/releases/latest/download"

if [[ -n "${ARRSUITE_REPOSITORY_RAW_URL:-}" ]]; then
  source_base_url="${ARRSUITE_REPOSITORY_RAW_URL%/}"
  ct_url="${source_base_url}/ct/arrsuite.sh"
  install_url="${source_base_url}/install/arrsuite-install.sh"
  version_url=""
else
  release_base_url="${ARRSUITE_RELEASE_BASE_URL:-$DEFAULT_RELEASE_BASE_URL}"
  release_base_url="${release_base_url%/}"
  ct_url="${release_base_url}/arrsuite-ct.sh"
  install_url="${release_base_url}/arrsuite-install.sh"
  version_url="${release_base_url}/VERSION"
fi

bootstrap_dir="$(mktemp -d)"
trap 'rm -rf "$bootstrap_dir"' EXIT

build_func="${bootstrap_dir}/build.func"
if [[ -n "${COMMUNITY_SCRIPTS_URL:-}" || -n "${ARRSUITE_REPOSITORY_RAW_URL:-}" ]]; then
  community_raw_url="${COMMUNITY_SCRIPTS_URL:-$DEFAULT_COMMUNITY_RAW_URL}"
  community_raw_url="${community_raw_url%/}"
  export ARRSUITE_HELPER_BASE_URL="${community_raw_url}/misc"
  curl -fsSL --retry 3 --retry-all-errors "${ARRSUITE_HELPER_BASE_URL}/build.func" -o "$build_func"
else
  version_file="${bootstrap_dir}/VERSION"
  curl -fsSL --retry 3 --retry-all-errors "${release_base_url}/VERSION" -o "$version_file"
  if ! grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$' "$version_file"; then
    echo "ArrSuite release version metadata is invalid." >&2
    exit 1
  fi
  if [[ "$release_base_url" == "$DEFAULT_RELEASE_BASE_URL" ]]; then
    release_base_url="https://github.com/donselkirk/arrsuite/releases/download/$(<"$version_file")"
    ct_url="${release_base_url}/arrsuite-ct.sh"
    install_url="${release_base_url}/arrsuite-install.sh"
    version_url="${release_base_url}/VERSION"
  fi
  export ARRSUITE_HELPER_BASE_URL="$release_base_url"
  export ARRSUITE_UPDATE_BASE_URL="${ARRSUITE_UPDATE_BASE_URL:-$DEFAULT_RELEASE_BASE_URL}"
  checksum_file="${bootstrap_dir}/SHA256SUMS"
  ct_script="${bootstrap_dir}/arrsuite-ct.sh"
  curl -fsSL --retry 3 --retry-all-errors "${release_base_url}/SHA256SUMS" -o "$checksum_file"
  for asset in build.func install.func tools.func core.func api.func error_handler.func; do
    curl -fsSL --retry 3 --retry-all-errors "${release_base_url}/${asset}" -o "${bootstrap_dir}/${asset}"
  done
  curl -fsSL --retry 3 --retry-all-errors "$ct_url" -o "$ct_script"
  if ! (cd "$bootstrap_dir" \
      && for asset in VERSION arrsuite-ct.sh build.func install.func tools.func core.func api.func error_handler.func; do
        grep -q " ${asset}$" SHA256SUMS || exit 1
      done \
      && sha256sum -c --ignore-missing SHA256SUMS >/dev/null); then
    echo "ArrSuite release assets failed checksum validation." >&2
    exit 1
  fi
  ct_url="$ct_script"
fi

# Keep the reviewed Community Scripts framework intact except for its helper
# base (patched in the release copies) and the two locations that fetch the
# application-specific installer (normal and APT-recovery retry paths).
# shellcheck disable=SC2016 # Match literal variable references in build.func.
sed -i \
  -e 's|"$COMMUNITY_SCRIPTS_URL/install/${var_install}.sh"|"$ARRSUITE_INSTALL_URL"|g' \
  -e 's|"https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/install/${var_install}.sh"|"$ARRSUITE_INSTALL_URL"|g' \
  "$build_func"

# shellcheck disable=SC2016 # Verify the literal reference inserted above.
redirect_count="$(grep -c 'curl -fsSL "$ARRSUITE_INSTALL_URL"' "$build_func" || true)"
if [[ "$redirect_count" -lt 2 ]]; then
  echo "Unable to redirect the Community Scripts installer URLs; upstream build.func may have changed." >&2
  exit 1
fi

export ARRSUITE_BUILD_FUNC_PATH="$build_func"
export ARRSUITE_INSTALL_URL="$install_url"
export ARRSUITE_VERSION_URL="$version_url"

if [[ -f "$ct_url" ]]; then
  source "$ct_url"
else
  source <(curl -fsSL --retry 3 --retry-all-errors "$ct_url")
fi
