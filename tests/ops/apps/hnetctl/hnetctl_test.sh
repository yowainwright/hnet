#!/usr/bin/env bash

set -euo pipefail

script_path=${BASH_SOURCE[0]}
script_parent=${script_path%/*}
script_dir=$(cd -- "$script_parent" && pwd)
# shellcheck source=tests/ops/test_support.sh
source "$script_dir/../../test_support.sh"

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
AGENT_TELEMETRY_STATE_DIR=$test_root/state
AGENT_TELEMETRY_LOCAL_TOKEN=$valid_token
AGENT_TELEMETRY_GATEWAY_TOKEN=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
EOF

  TELEMETRY_EDGE_ENV="$edge_env" \
    TELEMETRY_DOCKER_BIN="$test_root/bin/docker" \
    OPS_TEST_DOCKER_LOG="$docker_log" \
    "$repo_dir/ops/apps/hnetctl/hnetctl" edge-status
  assert_file "$test_root/state/zsh.jsonl"
  assert_file "$test_root/state/dotfiles.jsonl"

  sed "s/$valid_token/$invalid_token/" "$edge_env" >"$edge_env.invalid"
  if TELEMETRY_EDGE_ENV="$edge_env.invalid" \
    TELEMETRY_DOCKER_BIN="$test_root/bin/docker" \
    OPS_TEST_DOCKER_LOG="$docker_log" \
    "$repo_dir/ops/apps/hnetctl/hnetctl" edge-status >/dev/null 2>&1; then
    fail "Short edge ingest token was accepted."
  fi

  sed "s/AGENT_TELEMETRY_GATEWAY_TOKEN=.*/AGENT_TELEMETRY_GATEWAY_TOKEN=$valid_token/" \
    "$edge_env" >"$edge_env.duplicate"
  if TELEMETRY_EDGE_ENV="$edge_env.duplicate" \
    TELEMETRY_DOCKER_BIN="$test_root/bin/docker" \
    OPS_TEST_DOCKER_LOG="$docker_log" \
    "$repo_dir/ops/apps/hnetctl/hnetctl" edge-status >/dev/null 2>&1; then
    fail "Reused edge and gateway tokens were accepted."
  fi
}

test_hnetctl_prepares_gateway_tokens_file() {
  local studio_env="$test_root/studio.env"
  local tokens_file="$test_root/gateway-tokens"
  local token_a=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  local token_b=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  local content
  cat >"$studio_env" <<EOF
GATEWAY_PORT=14318
GRAFANA_PORT=2021
TAILSCALE_DNS_NAME=studio.example.ts.net
GF_SECURITY_ADMIN_USER=admin
TELEMETRY_TTL=336h
AGENT_TELEMETRY_GATEWAY_TOKENS=placeholder
AGENT_TELEMETRY_GATEWAY_TOKENS_FILE=$tokens_file
EOF

  (
    export TELEMETRY_STUDIO_ENV="$studio_env"
    export AGENT_TELEMETRY_GATEWAY_TOKENS="$token_a
$token_b"
    export GF_SECURITY_ADMIN_PASSWORD=aaaaaaaaaaaaaaaaaaaaaaaa
    export CLICKHOUSE_PASSWORD=bbbbbbbbbbbbbbbbbbbbbbbb
    export GRAFANA_CLICKHOUSE_PASSWORD=cccccccccccccccccccccccc
    # shellcheck source=/dev/null
    source <(sed '/^case "${1:-}"/,$d' "$repo_dir/ops/apps/hnetctl/hnetctl")
    load_studio_config resolve
    validate_studio_public_config
    validate_studio_secrets
    prepare_gateway_tokens_file
  )

  assert_file "$tokens_file"
  content=$(<"$tokens_file")
  assert_contains "$content" "$token_a"
  assert_contains "$content" "$token_b"

  if (
    # shellcheck source=/dev/null
    source <(sed '/^case "${1:-}"/,$d' "$repo_dir/ops/apps/hnetctl/hnetctl")
    validate_gateway_tokens "$token_a
$token_a"
  ) >/dev/null 2>&1; then
    fail "Duplicate gateway tokens were accepted."
  fi
}

test_hnetctl_lints_telemetry_chart() {
  local output
  output=$("$repo_dir/ops/apps/hnetctl/hnetctl" cluster-lint)
  assert_contains "$output" "1 chart(s) linted"
}

make_fake_tools
test_hnetctl_resolves_the_ops_telemetry_path
test_hnetctl_validates_edge_ingest_token
test_hnetctl_prepares_gateway_tokens_file
test_hnetctl_lints_telemetry_chart

echo "hnetctl tests passed."
