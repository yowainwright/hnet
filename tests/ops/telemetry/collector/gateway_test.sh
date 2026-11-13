#!/usr/bin/env bash

set -euo pipefail

main() {
  config=$(jq 'map(. + {tokenEnv: ("HNET_CLIENT_TOKEN_" + (.port | tostring))})' ops/telemetry/clients.example.json |
    jq -f ops/telemetry/collector/clients.jq)
  jq -e '.receivers["otlp/client_4318"].protocols.http.auth.authenticator == "bearertokenauth/client_4318"' <<<"$config" >/dev/null ||
    fail "Generated receiver does not bind its authenticator."
  jq -e '.processors["resource/client_4318"].attributes[0] == {key: "host.name", action: "upsert", value: "central"}' <<<"$config" >/dev/null ||
    fail "Generated receiver does not overwrite host identity."
  jq -e 'all(.service.pipelines[]; .processors == ["memory_limiter", "transform/privacy", "redaction/sensitive", "resource/client_4318", "resource/pipeline"])' <<<"$config" >/dev/null ||
    fail "Generated signals bypass existing privacy processors."

  echo "gateway collector security tests passed."
}

fail() {
  echo "$1" >&2
  exit 1
}

main
