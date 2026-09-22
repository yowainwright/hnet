#!/usr/bin/env bash

set -euo pipefail

script_path=${BASH_SOURCE[0]}
script_parent=${script_path%/*}
script_dir=$(cd -- "$script_parent" && pwd)
# shellcheck source=tests/ops/test_support.sh
source "$script_dir/../test_support.sh"

test_lint_wiring() {
  local fake_bin="$test_root/bin"
  local shellcheck_log="$test_root/shellcheck.log"
  local zsh_log="$test_root/zsh.log"
  local shfmt_log="$test_root/shfmt.log"
  local shellcheck_args shfmt_args
  : >"$shellcheck_log"
  : >"$zsh_log"
  : >"$shfmt_log"

  PATH="$fake_bin:$PATH" \
    OPS_TEST_SHELLCHECK_LOG="$shellcheck_log" \
    OPS_TEST_ZSH_LOG="$zsh_log" \
    OPS_TEST_SHFMT_LOG="$shfmt_log" \
    "$repo_dir/ops/scripts/lint.sh" --strict
  shellcheck_args=$(<"$shellcheck_log")
  assert_contains "$shellcheck_args" 'ops/scripts/lint.sh'
  assert_contains "$shellcheck_args" 'ops/apps/hnetctl/hnetctl'
  assert_contains "$shellcheck_args" 'ops/scripts/setup.sh'
  assert_contains "$shellcheck_args" 'ops/runners/setup.sh'
  assert_contains "$shellcheck_args" 'ops/runners/setup-all.sh'
  assert_contains "$shellcheck_args" 'ops/runners/doctor.sh'
  assert_contains "$shellcheck_args" 'tests/ops/scripts/lint_test.sh'
  assert_contains "$shellcheck_args" 'tests/ops/scripts/setup_test.sh'
  assert_contains "$shellcheck_args" 'tests/ops/runners/setup_test.sh'
  shfmt_args=$(<"$shfmt_log")
  assert_contains "$shfmt_args" 'ops/scripts/lint.sh'
  assert_contains "$shfmt_args" 'ops/apps/hnetctl/hnetctl'
  assert_contains "$shfmt_args" 'tests/ops/scripts/lint_test.sh'

  (cd "$repo_dir/ops/telemetry" &&
    PATH="$fake_bin:$PATH" \
      OPS_TEST_SHELLCHECK_LOG="$shellcheck_log" \
      OPS_TEST_ZSH_LOG="$zsh_log" \
      OPS_TEST_SHFMT_LOG="$shfmt_log" \
      "$repo_dir/ops/scripts/lint.sh" --strict)
}

test_lint_formatter_modes() {
  local no_shfmt_bin="$test_root/no-shfmt-bin"
  local optional_output
  mkdir -p "$no_shfmt_bin"
  ln -s "$test_root/bin/shellcheck" "$no_shfmt_bin/shellcheck"
  ln -s "$test_root/bin/zsh" "$no_shfmt_bin/zsh"

  if PATH="$no_shfmt_bin:/usr/bin:/bin" \
    OPS_TEST_SHELLCHECK_LOG="$test_root/shellcheck.log" \
    OPS_TEST_ZSH_LOG="$test_root/zsh.log" \
    "$repo_dir/ops/scripts/lint.sh" --strict >/dev/null 2>&1; then
    fail "Strict lint accepted a missing shfmt."
  fi

  optional_output=$(
    PATH="$no_shfmt_bin:/usr/bin:/bin" \
      OPS_TEST_SHELLCHECK_LOG="$test_root/shellcheck.log" \
      OPS_TEST_ZSH_LOG="$test_root/zsh.log" \
      "$repo_dir/ops/scripts/lint.sh" 2>&1
  )
  assert_contains "$optional_output" 'shfmt unavailable'
}

make_fake_tools
test_lint_wiring
test_lint_formatter_modes

echo "lint tests passed."
