#!/usr/bin/env bash

set -euo pipefail

config_file=ops/telemetry/collector/gateway.yaml

fail() {
  echo "$1" >&2
  exit 1
}

grep -Fq 'bearertokenauth/server:' "$config_file" || fail "Gateway server authenticator is missing."
grep -Fq 'authenticator: bearertokenauth/server' "$config_file" || fail "Gateway OTLP HTTP receiver is unauthenticated."

echo "gateway collector security tests passed."
