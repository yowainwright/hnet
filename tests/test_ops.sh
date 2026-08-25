#!/usr/bin/env bash

set -euo pipefail

script_path=${BASH_SOURCE[0]}
script_parent=${script_path%/*}
script_dir=$(cd -- "$script_parent" && pwd)
repo_dir=$(cd -- "$script_dir/.." && pwd)
tmp_dir="$repo_dir/tmp"
mkdir -p "$tmp_dir"
test_root=$(mktemp -d "$tmp_dir/hnet-tests.XXXXXX")

cleanup() {
  rm -rf "$test_root"
}

trap cleanup EXIT

fail() {
  echo "$1" >&2
  exit 1
}

assert_contains() {
  local haystack=$1 needle=$2
  [[ $haystack == *"$needle"* ]] || fail "Expected output to contain: $needle"
}

assert_file() {
  [[ -f $1 ]] || fail "Expected file: $1"
}

make_fake_tools() {
  local fake_bin="$test_root/bin"
  mkdir -p "$fake_bin"

  cat >"$fake_bin/shellcheck" <<'TOOL'
#!/bin/sh
printf '%s\n' "$@" >> "${OPS_TEST_SHELLCHECK_LOG:?}"
TOOL

  cat >"$fake_bin/zsh" <<'TOOL'
#!/bin/sh
printf '%s\n' "$@" >> "${OPS_TEST_ZSH_LOG:?}"
TOOL

  cat >"$fake_bin/shfmt" <<'TOOL'
#!/bin/sh
printf '%s\n' "$@" >> "${OPS_TEST_SHFMT_LOG:?}"
TOOL

  cat >"$fake_bin/docker" <<'TOOL'
#!/bin/sh
printf '%s\n' "$@" >> "${OPS_TEST_DOCKER_LOG:?}"
TOOL

  chmod +x "$fake_bin/shellcheck" "$fake_bin/zsh" "$fake_bin/shfmt" "$fake_bin/docker"
}

test_setup_installs_and_preserves_hooks() {
  local setup_repo="$test_root/setup-repo"
  local hooks_dir hook content hooks_path
  mkdir -p "$setup_repo/ops/scripts"
  git -C "$setup_repo" init -q
  ln -s "$repo_dir/ops/scripts/setup.sh" "$setup_repo/ops/scripts/setup.sh"

  (cd "$setup_repo" && ./ops/scripts/setup.sh >/dev/null)
  hooks_dir="$setup_repo/.git/hooks"
  for hook in pre-commit pre-push commit-msg; do
    hook_path="$hooks_dir/$hook"
    assert_file "$hook_path"
    [[ -x $hook_path ]] || fail "Hook is not executable: $hook_path"
  done

  hooks_path=$(git -C "$setup_repo" config --get core.hooksPath || true)
  [[ -z $hooks_path ]] || fail "Setup configured core.hooksPath unexpectedly."

  content=$(<"$hooks_dir/pre-commit")
  assert_contains "$content" './ops/scripts/lint.sh --strict'
  content=$(<"$hooks_dir/pre-push")
  assert_contains "$content" './tests/test_ops.sh'

  printf '%s\n' '# custom local hook' >"$hooks_dir/pre-commit"
  (cd "$setup_repo" && ./ops/scripts/setup.sh >/dev/null)
  content=$(<"$hooks_dir/pre-commit")
  assert_contains "$content" '# custom local hook'
}

test_commit_message_hook() {
  local hooks_dir="$test_root/setup-repo/.git/hooks"
  local valid_message="$test_root/valid-message"
  local invalid_message="$test_root/invalid-message"
  printf '%s\n' 'docs: verify local hooks' >"$valid_message"
  printf '%s\n' 'bad message' >"$invalid_message"

  "$hooks_dir/commit-msg" "$valid_message"
  if "$hooks_dir/commit-msg" "$invalid_message" >/dev/null 2>&1; then
    fail "Invalid commit message was accepted."
  fi
}

test_lint_and_validation_wiring() {
  local fake_bin="$test_root/bin"
  local shellcheck_log="$test_root/shellcheck.log"
  local zsh_log="$test_root/zsh.log"
  local shfmt_log="$test_root/shfmt.log"
  local docker_log="$test_root/docker.log"
  local shellcheck_args shfmt_args docker_args
  : >"$shellcheck_log"
  : >"$zsh_log"
  : >"$shfmt_log"
  : >"$docker_log"

  PATH="$fake_bin:$PATH" \
    OPS_TEST_SHELLCHECK_LOG="$shellcheck_log" \
    OPS_TEST_ZSH_LOG="$zsh_log" \
    OPS_TEST_SHFMT_LOG="$shfmt_log" \
    "$repo_dir/ops/scripts/lint.sh" --strict
  shellcheck_args=$(<"$shellcheck_log")
  assert_contains "$shellcheck_args" 'ops/scripts/lint.sh'
  assert_contains "$shellcheck_args" 'ops/scripts/setup.sh'
  assert_contains "$shellcheck_args" 'tests/test_ops.sh'
  shfmt_args=$(<"$shfmt_log")
  assert_contains "$shfmt_args" 'ops/scripts/lint.sh'
  assert_contains "$shfmt_args" 'tests/test_ops.sh'

  (cd "$repo_dir/ops/telemetry" &&
    PATH="$fake_bin:$PATH" \
      OPS_TEST_SHELLCHECK_LOG="$shellcheck_log" \
      OPS_TEST_ZSH_LOG="$zsh_log" \
      OPS_TEST_SHFMT_LOG="$shfmt_log" \
      "$repo_dir/ops/scripts/lint.sh" --strict)

  PATH="$fake_bin:$PATH" \
    OPS_TEST_SHELLCHECK_LOG="$shellcheck_log" \
    OPS_TEST_ZSH_LOG="$zsh_log" \
    OPS_TEST_SHFMT_LOG="$shfmt_log" \
    OPS_TEST_DOCKER_LOG="$docker_log" \
    "$repo_dir/ops/scripts/validate.sh"
  docker_args=$(<"$docker_log")
  assert_contains "$docker_args" 'compose'
  assert_contains "$docker_args" 'ops/telemetry/compose.mac-studio.yml'
  assert_contains "$docker_args" 'ops/telemetry/compose.edge.yml'
  assert_contains "$docker_args" 'config'
  assert_contains "$docker_args" '--quiet'
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

test_hnetctl_resolves_the_ops_telemetry_path() {
  local output exit_code=0
  output=$(
    cd "$repo_dir/ops/telemetry"
    env -u TELEMETRY_STUDIO_ENV -u TELEMETRY_EDGE_ENV \
      PATH="$test_root/bin:$PATH" \
      OPS_TEST_DOCKER_LOG="$test_root/hnetctl-docker.log" \
      "$repo_dir/ops/apps/hnetctl/hnetctl" status 2>&1
  ) || exit_code=$?

  [[ $exit_code -ne 0 ]] || fail "hnetctl status unexpectedly succeeded without configuration."
  assert_contains "$output" "$repo_dir/ops/telemetry/.env.mac-studio"
}

make_fake_tools
test_setup_installs_and_preserves_hooks
test_commit_message_hook
test_lint_and_validation_wiring
test_lint_formatter_modes
test_hnetctl_resolves_the_ops_telemetry_path

echo "Ops tests passed."
