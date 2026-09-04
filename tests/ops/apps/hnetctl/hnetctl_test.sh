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

write_studio_env() {
  local studio_env=$1
  cat >"$studio_env" <<EOF
GATEWAY_PORT=$TEST_GATEWAY_PORT
GATEWAY_PORT_MAC_MINI_1=$TEST_GATEWAY_PORT_MAC_MINI_1
GATEWAY_PORT_MAC_MINI_2=$TEST_GATEWAY_PORT_MAC_MINI_2
GRAFANA_PORT=$TEST_GRAFANA_PORT
TAILSCALE_DNS_NAME=$TEST_TAILSCALE_DNS_NAME
GF_SECURITY_ADMIN_USER=$TEST_GF_SECURITY_ADMIN_USER
GF_SECURITY_ADMIN_PASSWORD=$TEST_GF_SECURITY_ADMIN_PASSWORD
CLICKHOUSE_PASSWORD=$TEST_CLICKHOUSE_PASSWORD
GRAFANA_CLICKHOUSE_PASSWORD=$TEST_GRAFANA_CLICKHOUSE_PASSWORD
AGENT_TELEMETRY_MAC_STUDIO_TOKEN=$TEST_AGENT_TELEMETRY_MAC_STUDIO_TOKEN
AGENT_TELEMETRY_MAC_MINI_1_TOKEN=$TEST_AGENT_TELEMETRY_MAC_MINI_1_TOKEN
AGENT_TELEMETRY_MAC_MINI_2_TOKEN=$TEST_AGENT_TELEMETRY_MAC_MINI_2_TOKEN
TELEMETRY_TTL=$TEST_TELEMETRY_TTL
EOF
}

write_edge_env() {
  local edge_env=$1
  cat >"$edge_env" <<EOF
AGENT_TELEMETRY_UPSTREAM=https://studio.example.ts.net:4318
AGENT_TELEMETRY_HOST=edge-test
AGENT_TELEMETRY_INGEST_TOKEN=$TEST_AGENT_TELEMETRY_MAC_STUDIO_TOKEN
EOF
}

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
  local missing_env="$test_root/missing-studio.env"
  local output exit_code=0
  output=$(
    cd "$repo_dir/ops/telemetry"
    env TELEMETRY_STUDIO_ENV="$missing_env" \
      PATH="$test_root/bin:$PATH" \
      OPS_TEST_DOCKER_LOG="$test_root/hnetctl-docker.log" \
      "$repo_dir/ops/apps/hnetctl/hnetctl" status 2>&1
  ) || exit_code=$?

  [[ $exit_code -ne 0 ]] || fail "hnetctl status unexpectedly succeeded without configuration."
  assert_contains "$output" "$missing_env"
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

test_hnetctl_creates_cluster_secret_from_studio_config() {
  local studio_env="$test_root/studio.env"
  local kubectl_log="$test_root/kubectl.log"
  local kubectl_args
  write_studio_env "$studio_env"
  : >"$kubectl_log"

  env \
    PATH="$test_root/bin:$PATH" \
    TELEMETRY_STUDIO_ENV="$studio_env" \
    HNET_KUBE_RUNTIME=none \
    HNET_KUBE_NAMESPACE=telemetry-test \
    HNET_KUBE_SECRET=hnet-test-secrets \
    OPS_TEST_KUBECTL_LOG="$kubectl_log" \
    "$repo_dir/ops/apps/hnetctl/hnetctl" cluster-secrets

  kubectl_args=$(<"$kubectl_log")
  assert_contains "$kubectl_args" "namespace"
  assert_contains "$kubectl_args" "telemetry-test"
  assert_contains "$kubectl_args" "secret"
  assert_contains "$kubectl_args" "hnet-test-secrets"
  assert_contains "$kubectl_args" "--from-env-file="
}

test_hnetctl_opens_k9s_with_orbstack_context() {
  local home_dir="$test_root/home"
  local kubectl_log="$test_root/k9s-kubectl.log"
  local orbctl_log="$test_root/orbctl.log"
  local k9s_log="$test_root/k9s.log"
  local k9s_args
  mkdir -p "$home_dir/.orbstack/k8s"
  : >"$home_dir/.orbstack/k8s/config.yml"
  : >"$kubectl_log"
  : >"$orbctl_log"
  : >"$k9s_log"

  env \
    HOME="$home_dir" \
    PATH="$test_root/bin:$PATH" \
    OPS_TEST_KUBECTL_LOG="$kubectl_log" \
    OPS_TEST_ORBCTL_LOG="$orbctl_log" \
    OPS_TEST_K9S_LOG="$k9s_log" \
    "$repo_dir/ops/apps/hnetctl/hnetctl" k9s svc

  k9s_args=$(<"$k9s_log")
  assert_contains "$k9s_args" "--kubeconfig"
  assert_contains "$k9s_args" "$home_dir/.orbstack/k8s/config.yml"
  assert_contains "$k9s_args" "--context"
  assert_contains "$k9s_args" "orbstack"
  assert_contains "$k9s_args" "--namespace"
  assert_contains "$k9s_args" "telemetry"
  assert_contains "$k9s_args" "--command"
  assert_contains "$k9s_args" "svc"
}

test_hnetctl_mprocs_bootstraps_compose_and_kubernetes() {
  local home_dir="$test_root/mprocs-home"
  local studio_env="$test_root/mprocs-studio.env"
  local edge_env="$test_root/mprocs-edge.env"
  local docker_log="$test_root/mprocs-docker.log"
  local helm_log="$test_root/mprocs-helm.log"
  local kubectl_log="$test_root/mprocs-kubectl.log"
  local orbctl_log="$test_root/mprocs-orbctl.log"
  local curl_log="$test_root/mprocs-curl.log"
  local tailscale_log="$test_root/mprocs-tailscale.log"
  local mprocs_log="$test_root/mprocs.log"
  local helm_args mprocs_args orbctl_args
  mkdir -p "$home_dir/.orbstack/k8s"
  : >"$home_dir/.orbstack/k8s/config.yml"
  write_studio_env "$studio_env"
  write_edge_env "$edge_env"
  : >"$docker_log"
  : >"$helm_log"
  : >"$kubectl_log"
  : >"$orbctl_log"
  : >"$curl_log"
  : >"$tailscale_log"
  : >"$mprocs_log"

  env \
    HOME="$home_dir" \
    PATH="$test_root/bin:$PATH" \
    TELEMETRY_STUDIO_ENV="$studio_env" \
    TELEMETRY_EDGE_ENV="$edge_env" \
    HNET_MPROCS_LOG_DIR="$test_root/mprocs-logs" \
    OPS_TEST_DOCKER_LOG="$docker_log" \
    OPS_TEST_HELM_LOG="$helm_log" \
    OPS_TEST_KUBECTL_LOG="$kubectl_log" \
    OPS_TEST_ORBCTL_LOG="$orbctl_log" \
    OPS_TEST_CURL_LOG="$curl_log" \
    OPS_TEST_TAILSCALE_LOG="$tailscale_log" \
    OPS_TEST_MPROCS_LOG="$mprocs_log" \
    "$repo_dir/ops/apps/hnetctl/hnetctl" mprocs

  orbctl_args=$(<"$orbctl_log")
  helm_args=$(<"$helm_log")
  mprocs_args=$(<"$mprocs_log")
  assert_contains "$orbctl_args" "k8s"
  assert_contains "$helm_args" "upgrade"
  assert_contains "$helm_args" "--install"
  assert_contains "$mprocs_args" "--config"
  assert_contains "$mprocs_args" "$repo_dir/ops/mprocs/hnet.yaml"
  assert_contains "$mprocs_args" "--proc-list-title"
  assert_contains "$mprocs_args" "hnet"
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
test_hnetctl_creates_cluster_secret_from_studio_config
test_hnetctl_opens_k9s_with_orbstack_context
test_hnetctl_mprocs_bootstraps_compose_and_kubernetes
test_hnetctl_validates_gateway_tokens
test_hnetctl_rejects_duplicate_gateway_tokens

echo "hnetctl tests passed."
