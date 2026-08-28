#!/usr/bin/env bash

set -euo pipefail

script_path=${BASH_SOURCE[0]}
script_parent=${script_path%/*}
script_dir=$(cd -- "$script_parent" && pwd)
# shellcheck source=tests/ops/test_support.sh
source "$script_dir/../../test_support.sh"
# shellcheck source=tests/ops/constants.sh
source "$repo_dir/tests/ops/constants.sh"

hnetctl_source=$(sed '/^case "${1:-}"/,$d' "$repo_dir/ops/apps/hnetctl/hnetctl")

run_studio_validation() {
  env \
    GATEWAY_PORT="$TEST_GATEWAY_PORT" \
    GATEWAY_PORT_MAC_MINI_1="$TEST_GATEWAY_PORT_MAC_MINI_1" \
    GATEWAY_PORT_MAC_MINI_2="$TEST_GATEWAY_PORT_MAC_MINI_2" \
    GRAFANA_PORT="$TEST_GRAFANA_PORT" \
    TAILSCALE_DNS_NAME="$TEST_TAILSCALE_DNS_NAME" \
    GF_SECURITY_ADMIN_USER="$TEST_GF_SECURITY_ADMIN_USER" \
    TELEMETRY_TTL="$TEST_TELEMETRY_TTL" \
    GF_SECURITY_ADMIN_PASSWORD="$TEST_GF_SECURITY_ADMIN_PASSWORD" \
    CLICKHOUSE_PASSWORD="$TEST_CLICKHOUSE_PASSWORD" \
    GRAFANA_CLICKHOUSE_PASSWORD="$TEST_GRAFANA_CLICKHOUSE_PASSWORD" \
    AGENT_TELEMETRY_MAC_STUDIO_TOKEN="$TEST_AGENT_TELEMETRY_MAC_STUDIO_TOKEN" \
    AGENT_TELEMETRY_MAC_MINI_1_TOKEN="$TEST_AGENT_TELEMETRY_MAC_MINI_1_TOKEN" \
    AGENT_TELEMETRY_MAC_MINI_2_TOKEN="$TEST_AGENT_TELEMETRY_MAC_MINI_2_TOKEN" \
    bash -c "$hnetctl_source
validate_studio_public_config
validate_studio_secrets" "$repo_dir/ops/apps/hnetctl/hnetctl"
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

test_hnetctl_validates_edge_ingest_token() {
  local edge_env="$test_root/edge.env"
  local docker_log="$test_root/edge-docker.log"
  local valid_token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  local invalid_token=short
  cat >"$edge_env" <<EOF
AGENT_TELEMETRY_UPSTREAM=https://studio.example.ts.net:4318
AGENT_TELEMETRY_HOST=edge-test
AGENT_TELEMETRY_INGEST_TOKEN=$valid_token
EOF

  TELEMETRY_EDGE_ENV="$edge_env" \
    TELEMETRY_DOCKER_BIN="$test_root/bin/docker" \
    OPS_TEST_DOCKER_LOG="$docker_log" \
    "$repo_dir/ops/apps/hnetctl/hnetctl" edge-status

  sed "s/$valid_token/$invalid_token/" "$edge_env" >"$edge_env.invalid"
  if TELEMETRY_EDGE_ENV="$edge_env.invalid" \
    TELEMETRY_DOCKER_BIN="$test_root/bin/docker" \
    OPS_TEST_DOCKER_LOG="$docker_log" \
    "$repo_dir/ops/apps/hnetctl/hnetctl" edge-status >/dev/null 2>&1; then
    fail "Short edge ingest token was accepted."
  fi

}

test_hnetctl_lints_telemetry_chart() {
  local output
  output=$("$repo_dir/ops/apps/hnetctl/hnetctl" cluster-lint)
  assert_contains "$output" "1 chart(s) linted"
}

test_hnetctl_validates_gateway_tokens() {
  run_studio_validation
}

test_hnetctl_rejects_duplicate_gateway_tokens() {
  if env \
    GATEWAY_PORT="$TEST_GATEWAY_PORT" \
    GATEWAY_PORT_MAC_MINI_1="$TEST_GATEWAY_PORT_MAC_MINI_1" \
    GATEWAY_PORT_MAC_MINI_2="$TEST_GATEWAY_PORT_MAC_MINI_2" \
    GRAFANA_PORT="$TEST_GRAFANA_PORT" \
    TAILSCALE_DNS_NAME="$TEST_TAILSCALE_DNS_NAME" \
    GF_SECURITY_ADMIN_USER="$TEST_GF_SECURITY_ADMIN_USER" \
    TELEMETRY_TTL="$TEST_TELEMETRY_TTL" \
    GF_SECURITY_ADMIN_PASSWORD="$TEST_GF_SECURITY_ADMIN_PASSWORD" \
    CLICKHOUSE_PASSWORD="$TEST_CLICKHOUSE_PASSWORD" \
    GRAFANA_CLICKHOUSE_PASSWORD="$TEST_GRAFANA_CLICKHOUSE_PASSWORD" \
    AGENT_TELEMETRY_MAC_STUDIO_TOKEN="$TEST_AGENT_TELEMETRY_MAC_STUDIO_TOKEN" \
    AGENT_TELEMETRY_MAC_MINI_1_TOKEN="$TEST_AGENT_TELEMETRY_MAC_STUDIO_TOKEN" \
    AGENT_TELEMETRY_MAC_MINI_2_TOKEN="$TEST_AGENT_TELEMETRY_MAC_MINI_2_TOKEN" \
    bash -c "$hnetctl_source
validate_studio_secrets" "$repo_dir/ops/apps/hnetctl/hnetctl"; then
    fail "Duplicate gateway tokens were accepted."
  fi
}

make_fake_tools
test_hnetctl_resolves_the_ops_telemetry_path
test_hnetctl_validates_edge_ingest_token
test_hnetctl_lints_telemetry_chart
test_hnetctl_validates_gateway_tokens
test_hnetctl_rejects_duplicate_gateway_tokens

echo "hnetctl tests passed."
