#!/usr/bin/env bash

set -euo pipefail

config_file=ops/telemetry/collector/gateway.yaml

fail() {
  echo "$1" >&2
  exit 1
}

if grep -Fq 'bearertokenauth/server' "$config_file"; then
  fail "Gateway must rely on the private Tailscale boundary, not a fleet token."
fi
grep -Fq 'action: insert' "$config_file" || fail "Gateway must preserve edge host identities."
grep -Fq 'value: central-gateway' "$config_file" || fail "Gateway fallback identity is missing."

echo "gateway collector security tests passed."
