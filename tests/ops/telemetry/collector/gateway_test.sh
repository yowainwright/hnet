#!/usr/bin/env bash

set -euo pipefail

config_file=ops/telemetry/collector/gateway.yaml

fail() {
  echo "$1" >&2
  exit 1
}

for token_name in mac_studio mac_mini_1 mac_mini_2; do
  grep -Fq "bearertokenauth/$token_name" "$config_file" || fail "Gateway token is missing for $token_name."
done
for host_name in mac-studio mac-mini-1 mac-mini-2; do
  grep -Fq "value: $host_name" "$config_file" || fail "Gateway host binding is missing for $host_name."
done
for port in 4318 4319 4320; do
  grep -Fq "endpoint: 0.0.0.0:$port" "$config_file" || fail "Gateway receiver port $port is missing."
done
if grep -Fq 'action: insert' "$config_file"; then
  fail "Gateway must overwrite host identity with the authenticated producer binding."
fi

echo "gateway collector security tests passed."
