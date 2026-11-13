#!/usr/bin/env bash

set -euo pipefail

script_path=${BASH_SOURCE[0]}
script_parent=${script_path%/*}
script_dir=$(cd -- "$script_parent" && pwd)
repo_dir=$(cd -- "$script_dir/../.." && pwd)
refresh_hooks=false

case "${1:-}" in
'') ;;
--refresh) refresh_hooks=true ;;
*)
  echo "Usage: $0 [--refresh]" >&2
  exit 2
  ;;
esac

remove_legacy_pre_push_hook() {
  local hook_path="$hooks_dir/pre-push"
  [[ -f $hook_path ]] || return 0

  if grep -Fq 'pre-push: running tests' "$hook_path" &&
    grep -Fq './ops/scripts/validate.sh' "$hook_path"; then
    rm -f "$hook_path"
    echo "Removed obsolete $hook_path"
  else
    echo "Keeping existing $hook_path"
  fi

  return 0
}

install_hook() {
  local hook_name=$1 hook_path="$hooks_dir/$1"
  if [[ $refresh_hooks != true && (-e $hook_path || -L $hook_path) ]]; then
    echo "Keeping existing $hook_path"
    return
  fi
  case "$hook_name" in
  pre-commit)
    cat >"$hook_path" <<'HOOK'
#!/bin/sh

set -eu

repo_dir=$(git rev-parse --show-toplevel)
cd "$repo_dir"

echo "pre-commit: checking staged changes"
git --no-pager diff --cached --check
mise run lint
echo "pre-commit: passed"
HOOK
    ;;
  commit-msg)
    cat >"$hook_path" <<'HOOK'
#!/bin/sh

set -eu

commit_subject=$(sed -n '1p' "$1")
pattern='^(feat|fix|docs|style|refactor|test|chore)(\(.+\))?: .{1,72}$'

case "$commit_subject" in
  Merge\ *|Revert\ *) echo "commit-msg: passed"; exit 0 ;;
esac

if printf '%s\n' "$commit_subject" | grep -Eq "$pattern"; then
  echo "commit-msg: passed"
  exit 0
fi

echo "Invalid commit message format." >&2
echo "Expected: type(scope): description" >&2
echo "Types: feat, fix, docs, style, refactor, test, chore" >&2
exit 1
HOOK
    ;;
  *) fail "Unsupported hook: $hook_name" 2 ;;
  esac
  chmod +x "$hook_path"
  echo "Installed $hook_path"
}

prepare_hooks() {
  local git_root active_hooks_path
  cd "$repo_dir"
  git_root=$(git rev-parse --show-toplevel 2>/dev/null) || fail "Run this script inside the hnet repository."
  [[ $git_root == "$repo_dir" ]] || fail "This script must run from the hnet repository."
  clear_legacy_hooks_path
  active_hooks_path=$(git config --get core.hooksPath || true)
  [[ -z $active_hooks_path ]] || fail "Unset core.hooksPath before running setup: $active_hooks_path"
  locate_hooks_directory
}

fail() {
  echo "$1" >&2
  exit "${2:-1}"
}

clear_legacy_hooks_path() {
  local local_hooks_path
  local_hooks_path=$(git config --local --get core.hooksPath || true)
  if [[ $local_hooks_path == .githooks ]]; then
    git config --local --unset-all core.hooksPath
  fi
}

locate_hooks_directory() {
  local git_dir
  git_dir=$(git rev-parse --git-dir)
  case "$git_dir" in
  /*) ;;
  *) git_dir="$repo_dir/$git_dir" ;;
  esac
  hooks_dir="$git_dir/hooks"
  mkdir -p "$hooks_dir"
}

prepare_hooks

install_hook pre-commit
install_hook commit-msg
remove_legacy_pre_push_hook

echo "Installed hnet Git hooks in $hooks_dir"
