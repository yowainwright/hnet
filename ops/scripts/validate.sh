#!/usr/bin/env bash

set -euo pipefail

script_path=${BASH_SOURCE[0]}
script_parent=${script_path%/*}
script_dir=$(cd -- "$script_parent" && pwd)
repo_dir=$(cd -- "$script_dir/../.." && pwd)

fail() {
  echo "$1" >&2
  exit "${2:-1}"
}

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

cd "$repo_dir"
case "${1:-all}" in
--fast) validate_shell ;;
all)
  validate_shell
  validate_compose
  ;;
*) fail "Usage: $0 [--fast]" 2 ;;
esac
