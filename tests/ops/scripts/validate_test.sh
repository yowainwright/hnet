#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=tests/ops/test_support.sh
source "${BASH_SOURCE[0]%/*}/../test_support.sh"

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
  assert_contains "$docker_args" 'validate'
  assert_contains "$docker_args" 'collector/gateway.yaml'
  assert_contains "$docker_args" 'collector/edge.yaml'
  assert_contains "$docker_args" 'none'
  assert_contains "$docker_args" '--tmpfs'
  assert_contains "$(<"$helm_log")" 'lint'
  assert_contains "$(<"$helm_log")" 'ops/telemetry'
  assert_contains "$(<"$helm_log")" 'template'
}

test_validate_rejects_invalid_collector_config() {
  local docker_log="$test_root/invalid-collector.log" result=0
  write_validation_docker
  PATH="$test_root/bin:$PATH" OPS_TEST_DOCKER_LOG="$docker_log" \
    OPS_TEST_COLLECTOR_EXIT_CODE=7 \
    "$repo_dir/ops/scripts/validate.sh" --collectors >/dev/null 2>&1 || result=$?
  [[ $result -eq 7 ]] || fail "Collector configuration failure was not propagated."
  assert_contains "$(<"$docker_log")" 'collector/gateway.yaml'
  [[ $(<"$docker_log") != *collector/edge.yaml* ]] || fail "Validation continued after a collector failure."
}

write_validation_docker() {
  cat >"$test_root/bin/docker" <<'TOOL'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" >>"${OPS_TEST_DOCKER_LOG:?}"
for arg in "$@"; do
  [[ $arg != validate ]] || exit "${OPS_TEST_COLLECTOR_EXIT_CODE:-0}"
done
TOOL
  chmod +x "$test_root/bin/docker"
}

make_fake_tools
test_validate_wiring
test_validate_rejects_invalid_collector_config

echo "validate tests passed."
