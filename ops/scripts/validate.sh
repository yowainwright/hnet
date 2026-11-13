#!/usr/bin/env bash

set -euo pipefail

script_path=${BASH_SOURCE[0]}
script_parent=${script_path%/*}
script_dir=$(cd -- "$script_parent" && pwd)
repo_dir=$(cd -- "$script_dir/../.." && pwd)

validate_shell() {
  ./ops/scripts/lint.sh
}

validate_compose() {
  command -v docker >/dev/null 2>&1 || fail "Missing required command: docker"
  docker compose \
    --env-file ops/telemetry/.env.mac-studio.example \
    -f ops/telemetry/compose.mac-studio.yml \
    config --quiet
  docker compose \
    --env-file ops/telemetry/.env.edge.example \
    -f ops/telemetry/compose.edge.yml \
    config --quiet
}

validate_collectors() {
  local image
  command -v docker >/dev/null 2>&1 || fail "Missing required command: docker"
  image=$(sed -n 's/^  collector: //p' ops/telemetry/values.yaml)
  [[ -n $image ]] || fail "Missing collector image in Helm values."
  HNET_CLIENTS_CONFIG=$(jq 'map(. + {tokenEnv: ("HNET_CLIENT_TOKEN_" + (.port | tostring))})' ops/telemetry/clients.example.json | jq -c -f ops/telemetry/collector/clients.jq) \
    validate_collector_config gateway ops/telemetry/.env.mac-studio.example "$image"
  validate_collector_config edge ops/telemetry/.env.edge.example "$image"
}

validate_collector_config() {
  local name=$1 env_file=$2 image=$3
  local client_config=${HNET_CLIENTS_CONFIG:-}
  [[ -n $client_config ]] || client_config='{}'
  docker run --rm --network none --read-only --cap-drop ALL \
    --security-opt no-new-privileges \
    --tmpfs /var/lib/otelcol:rw,noexec,nosuid,size=1m,uid=10001,gid=10001,mode=0700 \
    --env-file "$env_file" \
    --env CLICKHOUSE_USER=otel_collector \
    --env "HNET_CLIENTS_CONFIG=$client_config" \
    --env HNET_CLIENT_TOKEN_4318=op://VALIDATION/agent-telemetry/central-token \
    --env AGENT_TELEMETRY_QUEUE_DIR=/var/lib/otelcol \
    --mount "type=bind,src=$repo_dir/ops/telemetry/collector/$name.yaml,dst=/etc/otelcol-contrib/config.yaml,readonly" \
    "$image" validate --config=/etc/otelcol-contrib/config.yaml --config=env:HNET_CLIENTS_CONFIG
}

validate_helm() {
  command -v helm >/dev/null 2>&1 || fail "Missing required command: helm"
  helm lint ops/telemetry
  helm template hnet-telemetry ops/telemetry --namespace telemetry >/dev/null
}

fail() {
  echo "$1" >&2
  exit "${2:-1}"
}

cd "$repo_dir"
case "${1:-all}" in
--fast) validate_shell ;;
--collectors) validate_collectors ;;
all)
  validate_shell
  validate_helm
  validate_compose
  validate_collectors
  ;;
*) fail "Usage: $0 [--fast|--collectors]" 2 ;;
esac
