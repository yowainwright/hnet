#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=tests/ops/test_support.sh
source "${BASH_SOURCE[0]%/*}/../test_support.sh"
# shellcheck source=ops/apps/hnetctl/clients.sh
source "$repo_dir/ops/apps/hnetctl/clients.sh"

compose_file=ops/telemetry/compose.mac-studio.yml

main() {
  test_authentication_settings
  test_generated_compose
  echo "central compose security tests passed."
}

test_authentication_settings() {
  grep -Fq 'GF_AUTH_PROXY_ENABLED=false' "$compose_file" || fail "Grafana auth proxy is not explicitly disabled."
  grep -Fq 'GF_AUTH_ANONYMOUS_ENABLED=false' "$compose_file" || fail "Grafana anonymous access is not disabled."
  if grep -Fq 'Tailscale-User-' "$compose_file"; then
    fail "Grafana still trusts forgeable Tailscale identity headers."
  fi
  if grep -Fq 'AGENT_TELEMETRY_INGEST_TOKEN' "$compose_file"; then
    fail "Central collector must not require the edge ingest token."
  fi
  grep -Fq -- '--config=env:HNET_CLIENTS_CONFIG' "$compose_file" ||
    fail "Generated collector config is not loaded."
  if grep -Eq 'AGENT_TELEMETRY_MAC_|GATEWAY_PORT_MAC_' "$compose_file"; then
    fail "Compose contains machine-specific client settings."
  fi
}

test_generated_compose() {
  clients_json=$(jq 'map(. + {tokenEnv: ("HNET_CLIENT_TOKEN_" + (.port | tostring))})' ops/telemetry/clients.example.json)
  HNET_CLIENTS_CONFIG=$(jq -c -f ops/telemetry/collector/clients.jq <<<"$clients_json")
  export HNET_CLIENTS_CONFIG
  client_compose_overlay >"$test_root/clients-compose.json"
  docker compose --env-file ops/telemetry/.env.mac-studio.example -f "$compose_file" \
    -f "$test_root/clients-compose.json" config --format=json >"$test_root/rendered.json"
  jq -e 'all(.services.collector.ports[]; .host_ip == "127.0.0.1")' "$test_root/rendered.json" >/dev/null ||
    fail "Generated client ports must remain loopback-only."
}

fail() {
  echo "$1" >&2
  exit 1
}

main
