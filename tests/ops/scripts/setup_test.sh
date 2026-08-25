#!/usr/bin/env bash

set -euo pipefail

script_path=${BASH_SOURCE[0]}
script_parent=${script_path%/*}
script_dir=$(cd -- "$script_parent" && pwd)
# shellcheck source=tests/ops/test_support.sh
source "$script_dir/../test_support.sh"

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
  assert_contains "$content" 'git --no-pager diff --cached --check'
  content=$(<"$hooks_dir/pre-push")
  assert_contains "$content" "find tests -type f -name '*_test.sh' -exec {} \\;"

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

test_setup_installs_and_preserves_hooks
test_commit_message_hook

echo "setup tests passed."
