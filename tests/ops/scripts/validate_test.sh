#!/usr/bin/env bash

set -euo pipefail

script_path=${BASH_SOURCE[0]}
script_parent=${script_path%/*}
script_dir=$(cd -- "$script_parent" && pwd)
# shellcheck source=tests/ops/test_support.sh
source "$script_dir/../test_support.sh"

test_validate_wiring() {
  local fake_bin="$test_root/bin"
  local shellcheck_log="$test_root/shellcheck.log"
  local zsh_log="$test_root/zsh.log"
  local shfmt_log="$test_root/shfmt.log"
  local helm_log="$test_root/helm.log"
  local docker_log="$test_root/docker.log"
  local docker_args
  : >"$shellcheck_log"
  : >"$zsh_log"
  : >"$shfmt_log"
  : >"$helm_log"
  : >"$docker_log"

  PATH="$fake_bin:$PATH" \
    OPS_TEST_SHELLCHECK_LOG="$shellcheck_log" \
    OPS_TEST_ZSH_LOG="$zsh_log" \
    OPS_TEST_SHFMT_LOG="$shfmt_log" \
    OPS_TEST_HELM_LOG="$helm_log" \
    OPS_TEST_DOCKER_LOG="$docker_log" \
    "$repo_dir/ops/scripts/validate.sh"
  docker_args=$(<"$docker_log")
  assert_contains "$docker_args" 'compose'
  assert_contains "$docker_args" 'ops/telemetry/compose.mac-studio.yml'
  assert_contains "$docker_args" 'ops/telemetry/compose.edge.yml'
  assert_contains "$docker_args" 'config'
  assert_contains "$docker_args" '--quiet'
  assert_contains "$(<"$helm_log")" 'lint'
  assert_contains "$(<"$helm_log")" 'ops/telemetry'
  assert_contains "$(<"$helm_log")" 'template'
}

make_fake_tools
test_validate_wiring

echo "validate tests passed."
