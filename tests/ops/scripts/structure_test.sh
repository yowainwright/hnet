#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=tests/ops/test_support.sh
source "${BASH_SOURCE[0]%/*}/../test_support.sh"

main() {
  test_filesystem_policy
  test_import_policy
  test_declaration_policy
  echo "Filesystem, import, and declaration policy tests passed."
}

test_filesystem_policy() {
  fs-lint check --config "$repo_dir/fs-lint.json" ops/apps/hnetctl/clients.sh ops/telemetry/collector/clients.jq
  expect_violation fs-lint check --config "$repo_dir/fs-lint.json" ops/telemetry/collector/macbook.yaml
  expect_violation fs-lint check --config "$repo_dir/fs-lint.json" ops/telemetry/clients.json
}

test_import_policy() {
  local fixture="$test_root/imports"
  mkdir -p "$fixture/ops" "$fixture/tests"
  printf 'VALUE = 1\n' >"$fixture/ops/private.py"
  printf 'VALUE = 1\n' >"$fixture/tests/private.py"
  printf 'from ops.private import VALUE\n' >"$fixture/tests/allowed.py"
  printf 'from tests.private import VALUE\n' >"$fixture/ops/forbidden.py"
  src-lint check tests/allowed.py --root "$fixture" --config "$repo_dir/.src-lintrc" --strict
  expect_violation src-lint check ops/forbidden.py --root "$fixture" --config "$repo_dir/.src-lintrc" --strict
}

test_declaration_policy() {
  printf 'main() { helper; }\nhelper() { :; }\nmain\n' >"$test_root/allowed.sh"
  printf 'helper() { :; }\nmain() { helper; }\nmain\n' >"$test_root/forbidden.sh"
  struct-lint --profile ci "$test_root/allowed.sh"
  expect_violation struct-lint --profile ci "$test_root/forbidden.sh"
}

expect_violation() {
  local result=0
  "$@" >/dev/null 2>&1 || result=$?
  [[ $result == 1 ]] || fail "Expected a lint violation with exit code 1; got $result."
}

main
