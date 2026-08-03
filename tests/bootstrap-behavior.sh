#!/usr/bin/env bash
set -Eeuo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_root/bin" "$test_root/release"

printf 'v9.9.9\n' >"$test_root/release/VERSION"
cat >"$test_root/release/build.func" <<'EOF_BUILD'
probe_normal() {
  curl -fsSL "$COMMUNITY_SCRIPTS_URL/install/${var_install}.sh"
}
probe_recovery() {
  curl -fsSL "https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/install/${var_install}.sh"
}
EOF_BUILD
cat >"$test_root/release/arrsuite-ct.sh" <<'EOF_CT'
[[ "$ARRSUITE_HELPER_BASE_URL" == "https://github.com/donselkirk/arrsuite/releases/download/v9.9.9" ]]
[[ "$ARRSUITE_INSTALL_URL" == "https://github.com/donselkirk/arrsuite/releases/download/v9.9.9/arrsuite-install.sh" ]]
printf 'bootstrap-ok\n' >"${BOOTSTRAP_TEST_ROOT}/result"
EOF_CT
for helper in install.func tools.func core.func api.func error_handler.func; do
  printf '# reviewed %s fixture\n' "$helper" >"$test_root/release/$helper"
done
(
  cd "$test_root/release"
  sha256sum VERSION arrsuite-ct.sh build.func install.func tools.func core.func api.func error_handler.func >SHA256SUMS
)

cat >"$test_root/bin/curl" <<'EOF_CURL'
#!/usr/bin/env bash
set -e
output=""
url=""
while (($#)); do
  case "$1" in
    -o) output="$2"; shift 2 ;;
    --retry|--connect-timeout) shift 2 ;;
    -*) shift ;;
    *) url="$1"; shift ;;
  esac
done
printf '%s\n' "$url" >>"${BOOTSTRAP_TEST_ROOT}/curl.log"
source_file="${BOOTSTRAP_TEST_ROOT}/release/${url##*/}"
[[ -f "$source_file" ]]
if [[ -n "$output" ]]; then
  cp "$source_file" "$output"
else
  cat "$source_file"
fi
EOF_CURL
chmod 0755 "$test_root/bin/curl"

BOOTSTRAP_TEST_ROOT="$test_root" PATH="$test_root/bin:$PATH" bash "$project_root/arrsuite.sh"
grep -qx 'bootstrap-ok' "$test_root/result"
grep -q '/releases/download/v9.9.9/build.func$' "$test_root/curl.log"
grep -q '/releases/download/v9.9.9/arrsuite-ct.sh$' "$test_root/curl.log"

printf '# tampered\n' >>"$test_root/release/build.func"
if BOOTSTRAP_TEST_ROOT="$test_root" PATH="$test_root/bin:$PATH" bash "$project_root/arrsuite.sh" >/dev/null 2>&1; then
  echo "Bootstrap accepted a helper with an invalid checksum." >&2
  exit 1
fi

echo "Bootstrap behavior checks passed."
