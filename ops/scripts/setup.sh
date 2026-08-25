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

fail() {
  echo "$1" >&2
  exit "${2:-1}"
}

cd "$repo_dir"
git_root=$(git rev-parse --show-toplevel 2>/dev/null) || fail "Run this script inside the hnet repository."
[[ $git_root == "$repo_dir" ]] || fail "This script must run from the hnet repository."

local_hooks_path=$(git config --local --get core.hooksPath || true)
if [[ $local_hooks_path == .githooks ]]; then
  git config --local --unset-all core.hooksPath
fi

active_hooks_path=$(git config --get core.hooksPath || true)
[[ -z $active_hooks_path ]] || fail "Unset core.hooksPath before running setup: $active_hooks_path"

git_dir=$(git rev-parse --git-dir)
case "$git_dir" in
/*) ;;
*) git_dir="$repo_dir/$git_dir" ;;
esac
hooks_dir="$git_dir/hooks"
mkdir -p "$hooks_dir"

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

git diff --cached --check
./ops/scripts/lint.sh --strict
HOOK
    ;;
  pre-push)
    cat >"$hook_path" <<'HOOK'
#!/bin/sh

set -eu

repo_dir=$(git rev-parse --show-toplevel)
cd "$repo_dir"

./tests/test_ops.sh
./ops/scripts/validate.sh
HOOK
    ;;
  commit-msg)
    cat >"$hook_path" <<'HOOK'
#!/bin/sh

set -eu

commit_subject=$(sed -n '1p' "$1")
pattern='^(feat|fix|docs|style|refactor|test|chore)(\(.+\))?: .{1,72}$'

case "$commit_subject" in
  Merge\ *|Revert\ *) exit 0 ;;
esac

if printf '%s\n' "$commit_subject" | grep -Eq "$pattern"; then
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

install_hook pre-commit
install_hook pre-push
install_hook commit-msg

echo "Installed hnet Git hooks in $hooks_dir"
