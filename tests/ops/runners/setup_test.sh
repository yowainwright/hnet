#!/usr/bin/env bash

set -euo pipefail

script_path=${BASH_SOURCE[0]}
script_dir=$(cd -- "${script_path%/*}" && pwd)
repo_dir=$(cd -- "$script_dir/../../.." && pwd)
# shellcheck source=tests/ops/test_support.sh
source "$script_dir/../test_support.sh"

make_runner_fakes() {
  local fake_bin="$test_root/runner-bin"
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
case "${1:-}" in
  auth) exit 0 ;;
  *) exit 0 ;;
esac
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
  output=$("$repo_dir/ops/runners/setup.sh" --help)
  assert_contains "$output" '--repo OWNER/REPO'
  assert_contains "$output" '--dry-run'
}

test_dry_run() {
  local fake_bin output runner_root
  fake_bin=$(make_runner_fakes)
  runner_root="$HOME/.hnet-test-runners-$$"
  output=$(PATH="$fake_bin:$PATH" HNET_RUNNER_ROOT="$runner_root" \
    "$repo_dir/ops/runners/setup.sh" --repo yowainwright/hnet --dry-run)
  assert_contains "$output" 'Would register yowainwright/hnet'
  assert_contains "$output" 'Would use labels: self-hosted,macos,ci,hnet-ci'
  [[ ! -e $runner_root ]] || fail 'Dry run created runner files.'
}

test_setup_rejects_unknown_repository() {
  local fake_bin
  fake_bin=$(make_runner_fakes)
  if PATH="$fake_bin:$PATH" "$repo_dir/ops/runners/setup.sh" \
    --repo 'bad repo/name' --dry-run >/dev/null 2>&1; then
    fail 'Invalid repository was accepted.'
  fi
}

test_help
test_dry_run
test_setup_rejects_unknown_repository
echo "runner setup tests passed."
