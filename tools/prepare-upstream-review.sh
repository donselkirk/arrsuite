#!/usr/bin/env bash
set -Eeuo pipefail

project_root="${ARRSUITE_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
lock_file="${project_root}/tools/upstream-lock.json"
report_dir="${UPSTREAM_REPORT_DIR:-${project_root}/upstream-report}"
pending_file="${project_root}/upstream-review/pending.md"
api_base="${GITHUB_API_URL:-https://api.github.com}"
fixture_dir="${UPSTREAM_FIXTURE_DIR:-}"
curl_args=(-fsSL --retry 3 --retry-all-errors --connect-timeout 15)
probe_args=(-fsSL --connect-timeout 15)
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  probe_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

command -v jq >/dev/null || { echo "jq is required." >&2; exit 2; }
command -v curl >/dev/null || { echo "curl is required." >&2; exit 2; }
command -v git >/dev/null || { echo "git is required." >&2; exit 2; }

mkdir -p "$report_dir"
rm -f "${report_dir}"/*.diff "${report_dir}/summary.md" "${report_dir}/pr-body.md" \
  "${report_dir}/agent-body.md" "${report_dir}/application-changes.tsv"
helper_changes=()
application_changes=()

fetch_source() {
  local repository="$1" path="$2" destination="$3" metadata_url metadata
  if [[ -n "$fixture_dir" ]]; then
    local fixture="${fixture_dir}/${repository}/${path}"
    [[ -f "$fixture" ]] || return 2
    cp "$fixture" "$destination"
    git hash-object "$destination"
    return 0
  fi

  metadata_url="${api_base}/repos/${repository}/contents/${path}?ref=main"
  metadata="$(curl "${curl_args[@]}" "$metadata_url")" || return 2
  jq -r '.content' <<<"$metadata" | base64 -d >"$destination"
  jq -r '.sha' <<<"$metadata"
}

patch_reviewed_helper() {
  local helper="$1" file="$2"
  case "$helper" in
    build.func)
      # shellcheck disable=SC2016 # Insert literal runtime variable expressions.
      sed -i \
        -e 's|_FUNC_BASE="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc"|_FUNC_BASE="${ARRSUITE_HELPER_BASE_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc}"|' \
        -e 's|source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/tools.func)|source <(curl -fsSL "${ARRSUITE_HELPER_BASE_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc}/tools.func")|' \
        -e 's|_func_url="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/install.func"|_func_url="${ARRSUITE_HELPER_BASE_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc}/install.func"|' \
        -e 's|source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/install.func)|source <(curl -fsSL "${ARRSUITE_HELPER_BASE_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc}/install.func")|' \
        "$file"
      [[ "$(grep -c 'ARRSUITE_HELPER_BASE_URL' "$file")" -eq 4 ]] || return 1
      ;;
    install.func)
      # shellcheck disable=SC2016 # Insert literal runtime variable expressions.
      sed -i \
        -e 's|_FUNC_BASE="https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc"|_FUNC_BASE="${ARRSUITE_HELPER_BASE_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc}"|' \
        -e 's|tools_content=$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/tools.func)|tools_content=$(curl -fsSL "${ARRSUITE_HELPER_BASE_URL:-https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc}/tools.func")|' \
        "$file"
      [[ "$(grep -c 'ARRSUITE_HELPER_BASE_URL' "$file")" -eq 2 ]] || return 1
      ;;
  esac
  bash -n "$file"
}

printf '# ArrSuite automated upstream review\n\n' >"${report_dir}/summary.md"
while IFS=$'\t' read -r category name kind repository path locked_blob vendored_path; do
  upstream_file="$(mktemp)"
  current_blob=""
  current_repository="$repository"
  if [[ -z "$fixture_dir" && "$category" == "application" \
    && "$repository" == "community-scripts/ProxmoxVE" ]]; then
    development_url="${api_base}/repos/community-scripts/ProxmoxVED/contents/${path}?ref=main"
    if development_metadata="$(curl "${probe_args[@]}" "$development_url" 2>/dev/null)"; then
      current_repository="community-scripts/ProxmoxVED"
      jq -r '.content' <<<"$development_metadata" | base64 -d >"$upstream_file"
      current_blob="$(jq -r '.sha' <<<"$development_metadata")"
    fi
  fi
  if [[ ! -s "$upstream_file" ]] \
    && ! current_blob="$(fetch_source "$current_repository" "$path" "$upstream_file")"; then
    rm -f "$upstream_file"
    # shellcheck disable=SC2016 # Markdown backticks are literal.
    printf -- '- **%s %s:** unable to query `%s/%s`\n' "$name" "$kind" "$repository" "$path" \
      >>"${report_dir}/summary.md"
    echo "Unable to retrieve all tracked upstream sources; no candidate was generated." >&2
    exit 2
  fi
  if [[ -z "${current_blob:-}" ]]; then
    current_blob="$(git hash-object "$upstream_file")"
  fi
  if [[ "$current_blob" == "$locked_blob" ]]; then
    rm -f "$upstream_file"
    continue
  fi

  old_file="$(mktemp)"
  if [[ "$category" == "helper" ]]; then
    cp "${project_root}/${vendored_path}" "$old_file"
  elif [[ -n "$fixture_dir" ]]; then
    : >"$old_file"
  else
    old_url="${api_base}/repos/${repository}/git/blobs/${locked_blob}"
    curl "${curl_args[@]}" "$old_url" | jq -r '.content' | base64 -d >"$old_file"
  fi
  diff -u --label "locked/${path}" --label "upstream/${path}" "$old_file" "$upstream_file" \
    >"${report_dir}/${name}-${kind}.diff" || true
  rm -f "$old_file"

  if [[ "$category" == "helper" ]]; then
    upstream_sha256="$(sha256sum "$upstream_file" | awk '{print $1}')"
    if ! patch_reviewed_helper "$name" "$upstream_file"; then
      rm -f "$upstream_file"
      printf -- '- **%s:** helper transformation or syntax validation failed\n' "$name" \
        >>"${report_dir}/summary.md"
      echo "Unsafe helper change detected; no candidate was generated." >&2
      exit 3
    fi
    install -m 0644 "$upstream_file" "${project_root}/${vendored_path}"
    vendored_sha256="$(sha256sum "${project_root}/${vendored_path}" | awk '{print $1}')"
    lock_tmp="$(mktemp)"
    jq --arg helper "$name" --arg blob "$current_blob" --arg upstream "$upstream_sha256" --arg vendored "$vendored_sha256" \
      '.helpers[$helper].blob=$blob | .helpers[$helper].upstream_sha256=$upstream | .helpers[$helper].vendored_sha256=$vendored' \
      "$lock_file" >"$lock_tmp"
    mv "$lock_tmp" "$lock_file"
    helper_changes+=("$name")
    # shellcheck disable=SC2016 # Markdown backticks are literal.
    printf -- '- Imported reviewed helper **%s**: `%s` → `%s`\n' "$name" "$locked_blob" "$current_blob" \
      >>"${report_dir}/summary.md"
  else
    application_changes+=("${name} ${kind}|${current_repository}|${path}|${locked_blob}|${current_blob}")
    # shellcheck disable=SC2016 # Markdown backticks are literal.
    printf -- '- Manual adaptation required for **%s %s**: `%s` → `%s`\n' "$name" "$kind" "$locked_blob" "$current_blob" \
      >>"${report_dir}/summary.md"
  fi
  rm -f "$upstream_file"
done < <(jq -r '
  (.helpers | to_entries[] | ["helper", .key, "source", .value.repository, .value.path, .value.blob, .value.vendored_path]),
  (.applications | to_entries[] as $app | $app.value | to_entries[] | ["application", $app.key, .key, .value.repository, .value.path, .value.blob, ""])
  | @tsv' "$lock_file")

if ((${#application_changes[@]})); then
  mkdir -p "$(dirname "$pending_file")"
  : >"${report_dir}/application-changes.tsv"
  {
    printf '# Pending Community Scripts application review\n\n'
    printf '> Do not merge this PR until every item is adapted, tested, locked, and this file is removed.\n\n'
    for entry in "${application_changes[@]}"; do
      IFS='|' read -r label repository path old_blob new_blob <<<"$entry"
      source="${repository}/${path}"
      # shellcheck disable=SC2016 # Markdown backticks are literal.
      printf -- '- [ ] **%s** — `%s`: `%s` → `%s`\n' "$label" "$source" "$old_blob" "$new_blob"
      app="${label% *}"
      kind="${label##* }"
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$app" "$kind" "$repository" "$path" "$old_blob" "$new_blob" \
        >>"${report_dir}/application-changes.tsv"
    done
  } >"$pending_file"
else
  rm -f "$pending_file"
  rmdir "$(dirname "$pending_file")" 2>/dev/null || true
fi

if ((${#helper_changes[@]} == 0 && ${#application_changes[@]} == 0)); then
  printf 'No tracked upstream changes were found.\n' >>"${report_dir}/summary.md"
  printf 'state=none\napplication_changes=false\n' >"${report_dir}/result.env"
else
  printf 'state=candidate\n' >"${report_dir}/result.env"
  if ((${#application_changes[@]})); then
    printf 'application_changes=true\n' >>"${report_dir}/result.env"
  else
    printf 'application_changes=false\n' >>"${report_dir}/result.env"
  fi
fi

{
  printf '## Automated Community Scripts review\n\n'
  cat "${report_dir}/summary.md"
  printf '\nThis PR is generated from a weekly deterministic review. It never merges automatically.\n'
  if ((${#application_changes[@]})); then
    # shellcheck disable=SC2016 # Markdown backticks are literal.
    printf '\n**Merge blocked:** resolve `upstream-review/pending.md` and remove it before merging.\n'
  fi
} >"${report_dir}/pr-body.md"

if ((${#application_changes[@]})); then
  {
    cat <<'EOF_AGENT_INTRO'
## Community Scripts application adaptation required

The weekly deterministic review found application behavior changes that require semantic review by the Codex GitHub Action.

EOF_AGENT_INTRO
    cat "$pending_file"
    cat <<'EOF_AGENT_TASK'

## Required work

- Run `bash tools/prepare-upstream-review.sh` to reproduce the current report and focused diffs.
- Review each changed upstream installer/CT script against the corresponding `apps/*.sh` module and templates.
- Adapt ArrSuite only where upstream behavior requires it; preserve ArrSuite-specific ports, safety, backups, and rollback behavior.
- Advance every resolved application blob in `tools/upstream-lock.json`.
- Import any mechanically safe helper changes produced by the preparer.
- Remove `upstream-review/pending.md` only after every listed change is resolved.
- Run `bash tools/build-artifacts.sh`, `bash tests/static-checks.sh`, and `git diff --check`.
- Leave the completed, validated changes in the working tree. The workflow opens the merge-ready pull request separately; never merge it.

The pull request must summarize the upstream behavior changes, ArrSuite adaptations, tests run, and any Proxmox validation still required.
EOF_AGENT_TASK
  } >"${report_dir}/agent-body.md"
fi

cat "${report_dir}/summary.md"
