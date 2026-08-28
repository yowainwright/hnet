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

echo "central compose security tests passed."
