#!/usr/bin/env bash
set -Eeuo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release_version="${1:?usage: build-release-assets.sh VERSION [OUTPUT_DIR]}"
output_dir="${2:-${project_root}/dist}"
[[ "$release_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
  echo "Invalid release version: ${release_version}" >&2
  exit 2
}

compatibility_file="${project_root}/release/COMPATIBILITY"
compatibility_schema="$(sed -n 's/^schema=//p' "$compatibility_file")"
minimum_direct_version="$(sed -n 's/^minimum_direct_version=//p' "$compatibility_file")"
bridge_version="$(sed -n 's/^bridge_version=//p' "$compatibility_file")"
[[ "$compatibility_schema" == "1" \
  && "$minimum_direct_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ \
  && "$bridge_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ \
  && "$(printf '%s\n%s\n' "$minimum_direct_version" "$bridge_version" | sort -V | sed -n '1p')" == "$minimum_direct_version" \
  && "$bridge_version" != "$release_version" \
  && "$(printf '%s\n%s\n' "$bridge_version" "$release_version" | sort -V | sed -n '1p')" == "$bridge_version" ]] || {
  echo "Invalid release upgrade compatibility policy." >&2
  exit 2
}

mkdir -p "$output_dir"
printf '%s\n' "$release_version" >"${output_dir}/VERSION"
install -m 0644 "$compatibility_file" "${output_dir}/COMPATIBILITY"
install -m 0755 "${project_root}/arrsuite.sh" "${output_dir}/arrsuite.sh"
install -m 0755 "${project_root}/ct/arrsuite.sh" "${output_dir}/arrsuite-ct.sh"
install -m 0755 "${project_root}/install/arrsuite-install.sh" "${output_dir}/arrsuite-install.sh"
install -m 0755 "${project_root}/tools/arrsuite-manager" "${output_dir}/arrsuite-manager"
install -m 0755 "${project_root}/tools/arrsuite-motd.sh" "${output_dir}/arrsuite-motd.sh"
install -m 0755 "${project_root}/tools/fix-console-autologin.sh" "${output_dir}/fix-console-autologin.sh"
install -m 0755 "${project_root}/tools/seerr-backup.sh" "${output_dir}/seerr-backup.sh"
for helper in build.func install.func tools.func core.func api.func error_handler.func; do
  install -m 0644 "${project_root}/vendor/community-scripts/misc/${helper}" "${output_dir}/${helper}"
done

(
  cd "$output_dir"
  sha256sum VERSION COMPATIBILITY arrsuite-manager >SHA256SUMS
  for asset in *.sh *.func; do
    sha256sum -- "$asset" >>SHA256SUMS
  done
  sha256sum -c SHA256SUMS >/dev/null
)
