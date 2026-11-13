#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=tests/ops/test_support.sh
source "${BASH_SOURCE[0]%/*}/../test_support.sh"

make_dependency_fakes() {
  mkdir -p "$test_root/bin"
  printf '#!/bin/sh\nprintf "Darwin\\n"\n' >"$test_root/bin/uname"
  cat >"$test_root/bin/mise" <<'TOOL'
#!/bin/sh
printf '%s\n' "$@" >"${OPS_TEST_MISE_LOG:?}"
exit 73
TOOL
  cat >"$test_root/bin/gh" <<'TOOL'
#!/bin/sh
touch "${OPS_TEST_GH_MARKER:?}"
exit 1
TOOL
  chmod +x "$test_root/bin/uname" "$test_root/bin/mise" "$test_root/bin/gh"
}

test_dependency_failure_stops_runner_setup() {
  local script=$1 result=0
  env PATH="$test_root/bin:$PATH" \
    OPS_TEST_MISE_LOG="$test_root/mise.log" \
    OPS_TEST_GH_MARKER="$test_root/gh-called" \
    "$repo_dir/ops/runners/$script" --install-deps || result=$?
  [[ $result -eq 73 ]] || fail "Runner setup ignored dependency installation failure."
  assert_contains "$(<"$test_root/mise.log")" "$repo_dir"
  assert_contains "$(<"$test_root/mise.log")" 'install'
  [[ ! -e $test_root/gh-called ]] || fail "Runner setup called GitHub after installation failed."
}

make_dependency_fakes
test_dependency_failure_stops_runner_setup setup.sh
test_dependency_failure_stops_runner_setup setup-all.sh
echo "Runner dependency failure tests passed."
