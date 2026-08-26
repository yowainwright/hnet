#!/usr/bin/env bash

set -euo pipefail

config_file=ops/telemetry/collector/edge.yaml

fail() {
  echo "$1" >&2
  exit 1
}

grep -Fq 'bearertokenauth/server:' "$config_file" || fail "Edge collector server authenticator is missing."
grep -Fq 'bearertokenauth/client:' "$config_file" || fail "Edge collector client authenticator is missing."
[[ $(grep -Fc 'authenticator: bearertokenauth/server' "$config_file") -eq 2 ]] || fail "Both edge OTLP protocols must require authentication."
grep -Fq 'authenticator: bearertokenauth/client' "$config_file" || fail "Edge-to-central export is not authenticated."

echo "edge collector security tests passed."
