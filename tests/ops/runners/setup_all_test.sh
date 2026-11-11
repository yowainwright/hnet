#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=tests/ops/test_support.sh
source "${BASH_SOURCE[0]%/*}/../test_support.sh"

test_setup_all_dry_run() {
  local fake_bin output runner_root
  fake_bin=$(make_setup_all_fakes)
  runner_root="$HOME/.hnet-test-runners-all-$$"
  output=$(PATH="$fake_bin:$PATH" HNET_RUNNER_ROOT="$runner_root" \
    "$repo_dir/ops/runners/setup-all.sh" --account yowainwright --dry-run)
  assert_contains "$output" 'Setting up runner 1: yowainwright/hnet'
  assert_contains "$output" 'Setting up runner 2: yowainwright/private-tools'
  assert_contains "$output" 'Prepared 2 private-repository runner(s).'
  [[ ! -e $runner_root ]] || fail 'Dry run created runner files.'
}

make_setup_all_fakes() {
  local fake_bin="$test_root/setup-all-bin"
  mkdir -p "$fake_bin"
  cat >"$fake_bin/uname" <<'TOOL'
#!/bin/sh
case "${1:-}" in
  -s) printf '%s\n' Darwin ;;
  -m) printf '%s\n' arm64 ;;
esac
TOOL
  cat >"$fake_bin/gh" <<'TOOL'
#!/bin/sh
if [ "${1:-}" = auth ]; then
  exit 0
fi
if [ "${1:-}" = repo ]; then
  printf '%s\n' yowainwright/hnet yowainwright/private-tools
  exit 0
fi
exit 0
TOOL
  cat >"$fake_bin/launchctl" <<'TOOL'
#!/bin/sh
exit 0
TOOL
  chmod +x "$fake_bin/uname" "$fake_bin/gh" "$fake_bin/launchctl"
  printf '%s\n' "$fake_bin"
}

test_help() {
  local output
  output=$("$repo_dir/ops/runners/setup-all.sh" --help)
  assert_contains "$output" '--account ACCOUNT'
  assert_contains "$output" '--dry-run'
}

test_setup_all_dry_run
test_help
echo "runner setup-all tests passed."
