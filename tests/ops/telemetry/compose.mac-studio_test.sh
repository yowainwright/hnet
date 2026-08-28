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
grep -Fq 'gateway_tokens' "$compose_file" || fail "Gateway token secret is not mounted."
grep -Fq 'AGENT_TELEMETRY_GATEWAY_TOKENS_FILE' "$compose_file" || fail "Gateway token file is not configured."

echo "central compose security tests passed."
