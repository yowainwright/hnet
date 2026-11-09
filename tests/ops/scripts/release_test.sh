#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=tests/ops/test_support.sh
source "${BASH_SOURCE[0]%/*}/../test_support.sh"

release_version=$(<"$repo_dir/VERSION")
passing_checks='[{"check_runs":[{"id":1,"name":"validate","status":"completed","conclusion":"success","app":{"id":15368}},{"id":2,"name":"macos-client","status":"completed","conclusion":"success","app":{"id":15368}}]}]'

main() {
  release_fake_tools
  test_release_preview
  test_release_publish_guards
  test_release_publish
  echo "Release automation tests passed."
}

test_release_preview() {
  local output
  output=$(run_release)
  assert_contains "$output" 'nothing published'
  assert_file "$test_root/output/hnet-$release_version-NOTES.md"
  [[ ! -e $test_root/gh.log ]] || fail "Preview contacted GitHub."
}

test_release_publish_guards() {
  RELEASE_TEST_DIRTY=changed expect_release_failure
  RELEASE_TEST_REMOTE=different expect_release_failure
  RELEASE_TEST_PRIVATE=true expect_release_failure
  RELEASE_TEST_TAG_COUNT=1 expect_release_failure
  RELEASE_TEST_CHECKS='[{"check_runs":[]}]' expect_release_failure
  local stale_checks
  stale_checks=$(jq '.[0].check_runs += [{id:3,name:"validate",status:"completed",conclusion:"failure",app:{id:15368}}]' <<<"$passing_checks")
  RELEASE_TEST_CHECKS="$stale_checks" expect_release_failure
}

test_release_publish() {
  local arguments
  run_release --publish >/dev/null
  assert_file "$test_root/publish.log"
  arguments=$(<"$test_root/publish.log")
  assert_contains "$arguments" '--prerelease'
  assert_contains "$arguments" '--latest=false'
  assert_contains "$arguments" '844a5cff958338a52d2a59cfeb7672c00fc2682c'
  assert_contains "$arguments" "hnet-$release_version-darwin-arm64.tar.gz"
  assert_contains "$arguments" "hnet-$release_version-darwin-amd64.tar.gz"
  assert_contains "$arguments" "hnet-$release_version-SHA256SUMS"
}

expect_release_failure() {
  if run_release --publish >/dev/null 2>&1; then
    fail "Release accepted a failed publication gate."
  fi
  [[ ! -e $test_root/publish.log ]] || fail "Failed preflight reached publication."
}

run_release() {
  PATH="$test_root/bin:$PATH" \
    HNET_RELEASE_DIR="$test_root/output" \
    RELEASE_TEST_PUBLISH_LOG="$test_root/publish.log" \
    RELEASE_TEST_GH_LOG="$test_root/gh.log" \
    RELEASE_TEST_CHECKS="${RELEASE_TEST_CHECKS:-$passing_checks}" \
    "$repo_dir/ops/scripts/release.sh" "$@"
}

release_fake_tools() {
  mkdir -p "$test_root/bin"
  release_fake_git
  release_fake_gh
  cat >"$test_root/bin/gitleaks" <<'TOOL'
#!/usr/bin/env bash
set -euo pipefail
if [[ ${1:-} == version ]]; then echo 8.30.1; fi
exit 0
TOOL
  chmod +x "$test_root/bin/git" "$test_root/bin/gh" "$test_root/bin/gitleaks"
}

release_fake_git() {
  cat >"$test_root/bin/git" <<'TOOL'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
rev-parse) echo 844a5cff958338a52d2a59cfeb7672c00fc2682c ;;
status) printf '%s' "${RELEASE_TEST_DIRTY:-}" ;;
ls-files) ;;
*) echo "Unexpected test git invocation" >&2; exit 1 ;;
esac
TOOL
}

release_fake_gh() {
  cat >"$test_root/bin/gh" <<'TOOL'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >>"${RELEASE_TEST_GH_LOG:?}"
if [[ $1 == release ]]; then
  [[ $2 == create ]] || exit 1
  printf '%s\n' "$@" >"${RELEASE_TEST_PUBLISH_LOG:?}"
  exit 0
fi
case "$*" in
*git/ref/heads/main*) echo "${RELEASE_TEST_REMOTE:-844a5cff958338a52d2a59cfeb7672c00fc2682c}" ;;
*git/matching-refs/tags/*) echo "${RELEASE_TEST_TAG_COUNT:-0}" ;;
*check-runs*) printf '%s\n' "${RELEASE_TEST_CHECKS:?}" ;;
*) echo "${RELEASE_TEST_PRIVATE:-false}" ;;
esac
TOOL
}

main
