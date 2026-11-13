#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=tests/ops/test_support.sh
source "${BASH_SOURCE[0]%/*}/../test_support.sh"

chart_dir=ops/telemetry

main() {
  command -v helm >/dev/null 2>&1 || fail "Missing required command: helm"
  test_chart_excludes_private_files
  helm lint "$chart_dir"
  rendered=$(helm template hnet-telemetry "$chart_dir" --namespace telemetry)
  test_default_workloads
  test_legacy_clients
  test_dynamic_clients
  test_matching_generators
  test_private_services
  echo "telemetry Helm tests passed."
}

test_chart_excludes_private_files() {
  local fixture="$test_root/chart" archive_files directory
  mkdir -p "$fixture/collector"
  cp "$chart_dir/Chart.yaml" "$chart_dir/.helmignore" "$fixture/"
  printf 'synthetic\n' >"$fixture/.env"
  printf 'synthetic\n' >"$fixture/.env.local"
  printf 'private-reference\n' >"$fixture/clients.json"
  printf 'safe\n' >"$fixture/collector/safe.yaml"
  for directory in backups data queues enrollments; do
    mkdir -p "$fixture/$directory/nested"
    printf 'synthetic\n' >"$fixture/$directory/nested/private.txt"
  done
  helm package "$fixture" --destination "$test_root" >/dev/null
  archive_files=$(tar -tzf "$test_root/hnet-telemetry-0.1.0.tgz")
  assert_contains "$archive_files" 'collector/safe.yaml'
  if grep -Eq '/(\.env[^/]*|clients\.json|backups|data|queues|enrollments)(/|$)' <<<"$archive_files"; then
    fail "Helm packaged private files."
  fi
}

test_default_workloads() {
  grep -Fq 'kind: StatefulSet' <<<"$rendered" || fail "Helm chart does not render a StatefulSet."
  grep -Fq 'kind: Deployment' <<<"$rendered" || fail "Helm chart does not render a Deployment."
  grep -Fq 'name: clickhouse' <<<"$rendered" || fail "ClickHouse service is missing."
  grep -Fq 'name: gateway' <<<"$rendered" || fail "Gateway service is missing."
  grep -Fq 'name: grafana' <<<"$rendered" || fail "Grafana service is missing."
  grep -Fq 'name: hnet-telemetry-secrets' <<<"$rendered" || fail "Secret reference is missing."
}

test_legacy_clients() {
  for token_name in AGENT_TELEMETRY_MAC_STUDIO_TOKEN AGENT_TELEMETRY_MAC_MINI_1_TOKEN AGENT_TELEMETRY_MAC_MINI_2_TOKEN; do
    grep -Fq "$token_name" <<<"$rendered" || fail "Helm gateway token is missing for $token_name."
  done
  for port in 4318 4319 4320; do
    grep -Fq "port: $port" <<<"$rendered" || fail "Helm gateway port $port is missing."
  done
}

test_dynamic_clients() {
  test_clients='[{"name":"travel-laptop","port":5010},{"name":"build-agent","port":5011}]'
  dynamic=$(helm template hnet-telemetry "$chart_dir" --namespace telemetry --set-json "clients=$test_clients")
  grep -Fq 'port: 5010' <<<"$dynamic" || fail "Configured gateway port is missing."
  grep -Fq 'name: HNET_CLIENT_TOKEN_5011' <<<"$dynamic" || fail "Configured token key is missing."
  grep -Fq -- '--config=env:HNET_CLIENTS_CONFIG' <<<"$dynamic" || fail "Generated client config is not loaded."
  if grep -Fq 'AGENT_TELEMETRY_MAC_STUDIO_TOKEN' <<<"$dynamic"; then
    fail "Explicit client inventory retained legacy credentials."
  fi
}

test_matching_generators() {
  helm_config=$(awk '/name: HNET_CLIENTS_CONFIG/ {getline; sub(/^ *value: /, ""); print; exit}' <<<"$dynamic" | jq -r . | jq -cS .)
  compose_config=$(jq 'map(. + {tokenEnv: ("HNET_CLIENT_TOKEN_" + (.port | tostring))})' <<<"$test_clients" |
    jq -cS -f "$chart_dir/collector/clients.jq")
  [[ $helm_config == "$compose_config" ]] || fail "Helm and Compose generate different client authentication or privacy pipelines."
}

test_private_services() {
  grep -Fq 'clusterIP: None' <<<"$rendered" || fail "Stateful services must use headless services."
  if grep -Fq 'type: LoadBalancer' <<<"$rendered"; then
    fail "Central services must not be public LoadBalancers."
  fi
}

main
