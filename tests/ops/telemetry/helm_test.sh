#!/usr/bin/env bash

set -euo pipefail

chart_dir=ops/telemetry

fail() {
  echo "$1" >&2
  exit 1
}

command -v helm >/dev/null 2>&1 || fail "Missing required command: helm"

helm lint "$chart_dir"
rendered=$(helm template hnet-telemetry "$chart_dir" --namespace telemetry)

grep -Fq 'kind: StatefulSet' <<<"$rendered" || fail "Helm chart does not render a StatefulSet."
grep -Fq 'kind: Deployment' <<<"$rendered" || fail "Helm chart does not render a Deployment."
grep -Fq 'name: clickhouse' <<<"$rendered" || fail "ClickHouse service is missing."
grep -Fq 'name: gateway' <<<"$rendered" || fail "Gateway service is missing."
grep -Fq 'name: grafana' <<<"$rendered" || fail "Grafana service is missing."
grep -Fq 'name: hnet-telemetry-secrets' <<<"$rendered" || fail "Secret reference is missing."
for token_name in AGENT_TELEMETRY_MAC_STUDIO_TOKEN AGENT_TELEMETRY_MAC_MINI_1_TOKEN AGENT_TELEMETRY_MAC_MINI_2_TOKEN; do
  grep -Fq "$token_name" <<<"$rendered" || fail "Helm gateway token is missing for $token_name."
done
for port in 4318 4319 4320; do
  grep -Fq "port: $port" <<<"$rendered" || fail "Helm gateway port $port is missing."
done
grep -Fq 'clusterIP: None' <<<"$rendered" || fail "Stateful services must use headless services."
if grep -Fq 'type: LoadBalancer' <<<"$rendered"; then
  fail "Central services must not be public LoadBalancers."
fi

echo "telemetry Helm tests passed."
