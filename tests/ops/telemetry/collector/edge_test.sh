#!/usr/bin/env bash

set -euo pipefail

config_file=ops/telemetry/collector/edge.yaml

fail() {
  echo "$1" >&2
  exit 1
}

grep -Fq 'bearertokenauth/server:' "$config_file" || fail "Edge collector server authenticator is missing."
[[ $(grep -Fc 'authenticator: bearertokenauth/server' "$config_file") -eq 2 ]] || fail "Both edge OTLP protocols must require authentication."
if grep -Fq 'filelog/' "$config_file"; then
  fail "Edge collector must not ingest unauthenticated local files."
fi

echo "edge collector security tests passed."
