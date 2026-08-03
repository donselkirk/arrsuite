#!/usr/bin/env bash
set -Eeuo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lock_file="${project_root}/tools/upstream-lock.json"
report_dir="${UPSTREAM_REPORT_DIR:-${project_root}/upstream-report}"
api_base="${GITHUB_API_URL:-https://api.github.com}"
changed=0
network_failures=0
curl_args=(-fsSL --retry 3 --retry-all-errors --connect-timeout 15)
[[ -z "${GITHUB_TOKEN:-}" ]] || curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")

command -v jq >/dev/null || { echo "jq is required." >&2; exit 2; }
command -v curl >/dev/null || { echo "curl is required." >&2; exit 2; }
mkdir -p "$report_dir"
rm -f "${report_dir}"/*.diff "${report_dir}/summary.md"

printf '# ArrSuite upstream check\n\n' >"${report_dir}/summary.md"
while IFS=$'\t' read -r category app kind repository path locked_blob vendored_path vendored_sha256; do
  if [[ "$category" == "helper" && ! -s "${project_root}/${vendored_path}" ]]; then
    printf -- '%s\n' "- **${app}:** vendored helper is missing: \`${vendored_path}\`" | tee -a "${report_dir}/summary.md"
    changed=1
  elif [[ "$category" == "helper" && "$(sha256sum "${project_root}/${vendored_path}" | awk '{print $1}')" != "$vendored_sha256" ]]; then
    printf -- '%s\n' "- **${app}:** vendored helper checksum differs from the reviewed lock" | tee -a "${report_dir}/summary.md"
    changed=1
  fi
  if [[ "$category" == "application" && "$repository" == "community-scripts/ProxmoxVE" ]]; then
    development_url="${api_base}/repos/community-scripts/ProxmoxVED/contents/${path}?ref=main"
    if development_metadata="$(curl "${curl_args[@]}" "$development_url" 2>/dev/null)"; then
      development_blob="$(jq -r '.sha' <<<"$development_metadata")"
      printf -- '%s\n' "- **${app} ${kind}:** now exists in \`community-scripts/ProxmoxVED\` (\`${development_blob}\`); review migration from the production fallback" \
        | tee -a "${report_dir}/summary.md"
      changed=1
    fi
  fi
  ref_url="${api_base}/repos/${repository}/contents/${path}?ref=main"
  metadata="$(curl "${curl_args[@]}" "$ref_url")" || {
    printf -- '%s\n' "- **${app} ${kind}:** unable to query \`${repository}/${path}\`" | tee -a "${report_dir}/summary.md"
    network_failures=$((network_failures + 1))
    continue
  }
  current_blob="$(jq -r '.sha' <<<"$metadata")"
  if [[ "$current_blob" == "$locked_blob" ]]; then
    printf -- '%s\n' "- ${app} ${kind}: unchanged (\`${current_blob}\`)" >>"${report_dir}/summary.md"
    continue
  fi

  changed=1
  printf -- '%s\n' \
    "- **${app} ${kind} changed:** \`${locked_blob}\` → \`${current_blob}\` (\`${repository}/${path}\`)" \
    | tee -a "${report_dir}/summary.md"
  old_url="${api_base}/repos/${repository}/git/blobs/${locked_blob}"
  old_file="$(mktemp)"
  new_file="$(mktemp)"
  curl "${curl_args[@]}" "$old_url" | jq -r '.content' | base64 -d >"$old_file"
  jq -r '.content' <<<"$metadata" | base64 -d >"$new_file"
  diff -u --label "locked/${path}" --label "upstream/${path}" "$old_file" "$new_file" \
    >"${report_dir}/${app}-${kind}.diff" || true
  rm -f "$old_file" "$new_file"
done < <(jq -r '
  (.helpers | to_entries[] | ["helper", .key, "source", .value.repository, .value.path, .value.blob, .value.vendored_path, .value.vendored_sha256]),
  (.applications | to_entries[] as $app | $app.value | to_entries[] | ["application", $app.key, .key, .value.repository, .value.path, .value.blob, "", ""])
  | @tsv' "$lock_file")

cat "${report_dir}/summary.md"
if ((network_failures)); then
  echo "${network_failures} upstream source(s) could not be queried; retry before reviewing upstream changes." >&2
  exit 2
fi
if ((changed)); then
  echo "Upstream changes require review; see ${report_dir}." >&2
  exit 1
fi
echo "All tracked Community Scripts sources are unchanged."
