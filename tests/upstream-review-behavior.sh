#!/usr/bin/env bash
set -Eeuo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

make_fixture_project() {
  local root="$1"
  mkdir -p "$root/tools" "$root/vendor/community-scripts/misc" \
    "$root/fixture/community-scripts/ProxmoxVE/misc" \
    "$root/fixture/community-scripts/ProxmoxVE/install"
}

review_root="$test_root/review"
make_fixture_project "$review_root"
printf 'tool helper old\n' >"$review_root/vendor/community-scripts/misc/tools.func"
printf 'tool helper old\n' >"$review_root/fixture/community-scripts/ProxmoxVE/misc/tools.func"
printf 'sonarr old\n' >"$review_root/fixture/community-scripts/ProxmoxVE/install/sonarr-install.sh"
old_helper_blob="$(git hash-object "$review_root/fixture/community-scripts/ProxmoxVE/misc/tools.func")"
old_app_blob="$(git hash-object "$review_root/fixture/community-scripts/ProxmoxVE/install/sonarr-install.sh")"
old_helper_sha="$(sha256sum "$review_root/vendor/community-scripts/misc/tools.func" | awk '{print $1}')"
cat >"$review_root/tools/upstream-lock.json" <<EOF_LOCK
{"helpers":{"tools.func":{"repository":"community-scripts/ProxmoxVE","path":"misc/tools.func","blob":"$old_helper_blob","upstream_sha256":"$old_helper_sha","vendored_path":"vendor/community-scripts/misc/tools.func","vendored_sha256":"$old_helper_sha"}},"applications":{"sonarr":{"install":{"repository":"community-scripts/ProxmoxVE","path":"install/sonarr-install.sh","blob":"$old_app_blob"}}}}
EOF_LOCK

ARRSUITE_PROJECT_ROOT="$review_root" UPSTREAM_FIXTURE_DIR="$review_root/fixture" \
  bash "$project_root/tools/prepare-upstream-review.sh" >/dev/null
grep -qx 'state=none' "$review_root/upstream-report/result.env"
grep -qx 'application_changes=false' "$review_root/upstream-report/result.env"
[[ ! -e "$review_root/upstream-review/pending.md" ]]

printf 'tool helper new\n' >"$review_root/fixture/community-scripts/ProxmoxVE/misc/tools.func"
printf 'sonarr new\n' >"$review_root/fixture/community-scripts/ProxmoxVE/install/sonarr-install.sh"
new_helper_blob="$(git hash-object "$review_root/fixture/community-scripts/ProxmoxVE/misc/tools.func")"
new_app_blob="$(git hash-object "$review_root/fixture/community-scripts/ProxmoxVE/install/sonarr-install.sh")"
ARRSUITE_PROJECT_ROOT="$review_root" UPSTREAM_FIXTURE_DIR="$review_root/fixture" \
  bash "$project_root/tools/prepare-upstream-review.sh" >/dev/null
grep -qx 'state=candidate' "$review_root/upstream-report/result.env"
grep -qx 'application_changes=true' "$review_root/upstream-report/result.env"
grep -qx 'tool helper new' "$review_root/vendor/community-scripts/misc/tools.func"
[[ "$(jq -r '.helpers["tools.func"].blob' "$review_root/tools/upstream-lock.json")" == "$new_helper_blob" ]]
[[ "$(jq -r '.applications.sonarr.install.blob' "$review_root/tools/upstream-lock.json")" == "$old_app_blob" ]]
grep -q 'Do not merge this PR' "$review_root/upstream-review/pending.md"
grep -q 'sonarr install' "$review_root/upstream-review/pending.md"
grep -q 'Codex GitHub Action' "$review_root/upstream-report/agent-body.md"
grep -q 'authoritative inputs for this run' "$review_root/upstream-report/agent-body.md"
# shellcheck disable=SC2016 # Markdown backticks are literal.
if grep -q 'Run `bash tools/prepare-upstream-review.sh`' "$review_root/upstream-report/agent-body.md"; then
  echo "Generated Codex task would destructively regenerate its supplied report." >&2
  exit 1
fi
expected_application_change="$(printf 'sonarr\tinstall\tcommunity-scripts/ProxmoxVE\tinstall/sonarr-install.sh\t%s\t%s' "$old_app_blob" "$new_app_blob")"
grep -Fqx "$expected_application_change" \
  "$review_root/upstream-report/application-changes.tsv"

printf 'sonarr old\n' >"$review_root/fixture/community-scripts/ProxmoxVE/install/sonarr-install.sh"
ARRSUITE_PROJECT_ROOT="$review_root" UPSTREAM_FIXTURE_DIR="$review_root/fixture" \
  bash "$project_root/tools/prepare-upstream-review.sh" >/dev/null
grep -qx 'state=none' "$review_root/upstream-report/result.env"
grep -qx 'application_changes=false' "$review_root/upstream-report/result.env"
[[ ! -e "$review_root/upstream-review/pending.md" ]]

# Simulate a retired helper path that is available only at its pinned ref.
helper_ref=1111111111111111111111111111111111111111
jq --arg ref "$helper_ref" '.helpers["tools.func"].ref = $ref' \
  "$review_root/tools/upstream-lock.json" >"$test_root/pinned-lock.json"
mv "$test_root/pinned-lock.json" "$review_root/tools/upstream-lock.json"
cp "$project_root/tools/check-upstream.sh" "$review_root/tools/"
mkdir -p "$test_root/bin"
cat >"$test_root/bin/curl" <<'EOF_CURL'
#!/usr/bin/env bash
set -euo pipefail
case "${@: -1}" in
  */community-scripts/ProxmoxVE/contents/misc/tools.func\?ref="$HELPER_REF")
    path=misc/tools.func ;;
  */community-scripts/ProxmoxVE/contents/install/sonarr-install.sh\?ref=main)
    path=install/sonarr-install.sh ;;
  *) exit 22 ;;
esac
file="$FIXTURE_ROOT/community-scripts/ProxmoxVE/$path"
jq -n --arg sha "$(git hash-object "$file")" --arg content "$(base64 -w0 "$file")" \
  '{sha: $sha, content: $content}'
EOF_CURL
chmod +x "$test_root/bin/curl"
(
  export PATH="$test_root/bin:$PATH" HELPER_REF="$helper_ref" FIXTURE_ROOT="$review_root/fixture"
  ARRSUITE_PROJECT_ROOT="$review_root" bash "$project_root/tools/prepare-upstream-review.sh" >/dev/null
  grep -qx 'state=none' "$review_root/upstream-report/result.env"
  bash "$review_root/tools/check-upstream.sh" >/dev/null
)

unsafe_root="$test_root/unsafe"
make_fixture_project "$unsafe_root"
printf 'old build helper\n' >"$unsafe_root/vendor/community-scripts/misc/build.func"
printf 'unexpected upstream build layout\n' >"$unsafe_root/fixture/community-scripts/ProxmoxVE/misc/build.func"
unsafe_old_blob="$(printf 'previous upstream build\n' | git hash-object --stdin)"
unsafe_sha="$(sha256sum "$unsafe_root/vendor/community-scripts/misc/build.func" | awk '{print $1}')"
cat >"$unsafe_root/tools/upstream-lock.json" <<EOF_UNSAFE
{"helpers":{"build.func":{"repository":"community-scripts/ProxmoxVE","path":"misc/build.func","blob":"$unsafe_old_blob","upstream_sha256":"$unsafe_sha","vendored_path":"vendor/community-scripts/misc/build.func","vendored_sha256":"$unsafe_sha"}},"applications":{}}
EOF_UNSAFE
if ARRSUITE_PROJECT_ROOT="$unsafe_root" UPSTREAM_FIXTURE_DIR="$unsafe_root/fixture" \
  bash "$project_root/tools/prepare-upstream-review.sh" >/dev/null 2>&1; then
  echo "Unsafe helper transformation unexpectedly succeeded." >&2
  exit 1
fi
grep -qx 'old build helper' "$unsafe_root/vendor/community-scripts/misc/build.func"

missing_root="$test_root/missing"
make_fixture_project "$missing_root"
cp "$review_root/tools/upstream-lock.json" "$missing_root/tools/upstream-lock.json"
cp "$review_root/vendor/community-scripts/misc/tools.func" "$missing_root/vendor/community-scripts/misc/tools.func"
if ARRSUITE_PROJECT_ROOT="$missing_root" UPSTREAM_FIXTURE_DIR="$missing_root/fixture" \
  bash "$project_root/tools/prepare-upstream-review.sh" >/dev/null 2>&1; then
  echo "Missing upstream source unexpectedly succeeded." >&2
  exit 1
fi

echo "Upstream review behavior checks passed."
