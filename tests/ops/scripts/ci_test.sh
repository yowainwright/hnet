#!/usr/bin/env bash

set -euo pipefail

script_path=${BASH_SOURCE[0]}
script_dir=$(cd -- "${script_path%/*}" && pwd)
# shellcheck source=tests/ops/test_support.sh
source "$script_dir/../test_support.sh"

test_ci_propagates_test_failures() {
  local fixture="$test_root/ci" run_script result=0
  run_script=$(sed -n '/- name: Run tests/,/^$/p' "$repo_dir/.github/workflows/test.yml" |
    sed '1,/run: |/d; /^$/d; s/^          //')
  [[ -n $run_script ]] || fail "CI test command is missing."
  mkdir -p "$fixture/tests"
  printf '#!/bin/sh\nexit 7\n' >"$fixture/tests/failing test_test.sh"
  chmod +x "$fixture/tests/failing test_test.sh"
  (cd "$fixture" && bash -eo pipefail -c "$run_script") || result=$?
  [[ $result -eq 7 ]] || fail "CI swallowed a test failure."
  printf '#!/bin/sh\nexit 0\n' >"$fixture/tests/failing test_test.sh"
  (cd "$fixture" && bash -eo pipefail -c "$run_script")
}

test_ci_propagates_test_failures
echo "CI failure propagation tests passed."
