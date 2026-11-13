#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=tests/ops/test_support.sh
source "${BASH_SOURCE[0]%/*}/../test_support.sh"

test_doctor_passes() {
  local fake_bin runner_root output
  fake_bin=$(make_doctor_fakes)
  runner_root="$test_root/doctor-runners"
  make_runner_dir "$runner_root/yowainwright-hnet"
  output=$(PATH="$fake_bin:$PATH" HNET_RUNNER_ROOT="$runner_root" \
    "$repo_dir/ops/runners/doctor.sh" --repo yowainwright/hnet)
  assert_contains "$output" 'service is running'
  assert_contains "$output" 'Runner doctor passed.'
}

make_runner_dir() {
  local runner_dir=$1
  mkdir -p "$runner_dir"
  printf '%s\n' '{"agentName":"hnet-mac"}' >"$runner_dir/.runner"
  printf '%s\n' 'yowainwright/hnet' >"$runner_dir/.hnet-repo"
  cat >"$runner_dir/svc.sh" <<'SERVICE'
#!/bin/sh
case "${1:-}" in
  status) printf '%s\n' 'service is running' ;;
esac
SERVICE
  chmod +x "$runner_dir/svc.sh"
}

test_help() {
  local output
  output=$("$repo_dir/ops/runners/doctor.sh" --help)
  assert_contains "$output" '--repo OWNER/REPO'
}

test_doctor_rejects_malformed_repositories() {
  local fake_bin invalid_repo output
  fake_bin=$(make_doctor_fakes)
  for invalid_repo in missing-slash /name owner/ owner/repo/extra; do
    if output=$(PATH="$fake_bin:$PATH" "$repo_dir/ops/runners/doctor.sh" \
      --repo "$invalid_repo" 2>&1); then
      fail 'Runner doctor accepted an invalid repository.'
    fi
    assert_contains "$output" 'repository must use OWNER/REPO format'
    [[ $output != *'runner directory is missing'* ]] || fail 'Doctor inspected an invalid repository.'
  done
}

make_doctor_fakes() {
  local fake_bin="$test_root/doctor-bin"
  mkdir -p "$fake_bin"
  cat >"$fake_bin/uname" <<'TOOL'
#!/bin/sh
printf '%s\n' Darwin
TOOL
  cat >"$fake_bin/gh" <<'TOOL'
#!/bin/sh
case "${1:-}" in
  auth) exit 0 ;;
  api) printf 'hnet-mac\tonline\tfalse\tself-hosted,macos,ci,hnet-ci\n' ;;
esac
TOOL
  for command_name in curl tar launchctl shellcheck shfmt helm zsh docker; do
    cat >"$fake_bin/$command_name" <<'TOOL'
#!/bin/sh
exit 0
TOOL
  done
  chmod +x "$fake_bin"/*
  printf '%s\n' "$fake_bin"
}

test_doctor_passes
test_help
test_doctor_rejects_malformed_repositories
echo "runner doctor tests passed."
