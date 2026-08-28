#!/usr/bin/env bash

set -euo pipefail

compose_file=ops/telemetry/compose.mac-studio.yml

fail() {
  echo "$1" >&2
  exit 1
}

grep -Fq 'GF_AUTH_PROXY_ENABLED=false' "$compose_file" || fail "Grafana auth proxy is not explicitly disabled."
grep -Fq 'GF_AUTH_ANONYMOUS_ENABLED=false' "$compose_file" || fail "Grafana anonymous access is not disabled."
if grep -Fq 'Tailscale-User-' "$compose_file"; then
  fail "Grafana still trusts forgeable Tailscale identity headers."
fi
if grep -Fq 'AGENT_TELEMETRY_INGEST_TOKEN' "$compose_file"; then
  fail "Central collector must not require the edge ingest token."
fi
grep -Fq "127.0.0.1:\${GATEWAY_PORT:-14318}:4318" "$compose_file" ||
  fail "Central gateway must remain loopback-only behind Tailscale."
grep -Fq "127.0.0.1:\${GATEWAY_PORT_MAC_MINI_1:-14319}:4319" "$compose_file" ||
  fail "mac-mini-1 gateway must remain loopback-only behind Tailscale."
grep -Fq "127.0.0.1:\${GATEWAY_PORT_MAC_MINI_2:-14320}:4320" "$compose_file" ||
  fail "mac-mini-2 gateway must remain loopback-only behind Tailscale."
for token_name in MAC_STUDIO MAC_MINI_1 MAC_MINI_2; do
  grep -Fq "AGENT_TELEMETRY_${token_name}_TOKEN" "$compose_file" ||
    fail "Gateway token is not passed for $token_name."
done

echo "central compose security tests passed."
