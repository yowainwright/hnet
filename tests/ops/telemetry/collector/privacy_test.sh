#!/usr/bin/env bash

set -euo pipefail

script_path=${BASH_SOURCE[0]}
script_dir=$(cd -- "${script_path%/*}" && pwd)
# shellcheck source=tests/ops/test_support.sh
source "$script_dir/../../test_support.sh"
collector_test_dir="$repo_dir/tests/ops/telemetry/collector"

image=$(sed -n 's/^  collector: //p' "$repo_dir/ops/telemetry/values.yaml")
container_id=
sink_container_id=
failures=0

cleanup_collector() {
  [[ -z $container_id ]] || docker rm --force "$container_id" >/dev/null 2>&1 || true
  [[ -z $sink_container_id ]] || docker rm --force "$sink_container_id" >/dev/null 2>&1 || true
  cleanup
}
trap cleanup_collector EXIT

write_transform() {
  local name=$1
  awk -v name="$name" '
    /^  transform\/privacy:/ { copying = 1; print "  transform/" name ":"; next }
    /^  redaction\/sensitive:/ { copying = 1; print "  redaction/" name ":"; next }
    copying && /^[^ ]|^  [^ ]/ { copying = 0 }
    copying { print }
  ' "$repo_dir/ops/telemetry/collector/$name.yaml"
}

write_collector_config() {
  local name=$1 processors="transform/$1, redaction/$1"
  printf 'receivers:\n  otlpjsonfile:\n    include: [/test/input.json]\n    start_at: beginning\nprocessors:\n'
  if [[ $name == combined ]]; then
    write_transform edge
    write_transform gateway
    processors='transform/edge, redaction/edge, transform/gateway, redaction/gateway'
  else
    write_transform "$name"
  fi
  write_file_exporter
  local signal
  for signal in traces logs metrics; do
    printf '    %s:\n      receivers: [otlpjsonfile]\n      processors: [%s]\n      exporters: [file]\n' "$signal" "$processors"
  done
}

write_file_exporter() {
  cat <<'CONFIG'
exporters:
  file:
    path: /test/output.json
    flush_interval: 100ms
service:
  telemetry:
    metrics:
      level: none
  pipelines:
CONFIG
}

wait_for_export() {
  local output=$1 attempt
  for ((attempt = 0; attempt < 100; attempt++)); do
    if [[ -s $output ]] && jq -e -s 'length >= 3' "$output" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  fail "Collector did not export all three synthetic signals."
}

compose_redaction_pattern() {
  local script
  script=$(sed '/^case "${1:-}"/,$d' "$repo_dir/ops/apps/hnetctl/hnetctl")
  script+=$'\nstudio_compose config --format json\nedge_compose config --format json'
  # Compose config escapes dollars for serialization; undo that display-only layer.
  env AGENT_TELEMETRY_REDACT_PATTERN="$1" TELEMETRY_DOCKER_BIN="$(command -v docker)" \
    TELEMETRY_STUDIO_ENV="$repo_dir/ops/telemetry/.env.mac-studio.example" \
    TELEMETRY_EDGE_ENV="$repo_dir/ops/telemetry/.env.edge.example" \
    bash -c "$script" "$repo_dir/ops/apps/hnetctl/hnetctl" |
    jq -e -r -s 'map(.services.collector.environment.AGENT_TELEMETRY_REDACT_PATTERN) | unique
      | if length == 1 then .[0] | split("$$") | join("$")
        else error("Compose personal patterns differ") end'
}

start_collector() {
  local fixture=$1
  local pattern=${2-'\Qsynthetic-private-email@example.invalid\E|\Qsynthetic-private-address (Unit 3)\E'}
  local personal_env=()
  [[ -z $pattern ]] || personal_env=(--env "AGENT_TELEMETRY_REDACT_PATTERN=$(compose_redaction_pattern "$pattern")")
  container_id=$(docker run --detach --network none --read-only --cap-drop ALL \
    --security-opt no-new-privileges --user "$(id -u):$(id -g)" \
    "${personal_env[@]}" \
    --mount "type=bind,src=$fixture,dst=/test" "$image" --config=/test/config.yaml)
}

stop_collector() {
  docker stop --time 10 "$container_id" >/dev/null
  docker rm "$container_id" >/dev/null
  container_id=
}

assert_signals() {
  jq -e -s -f "$collector_test_dir/privacy-assertions.jq" "$1" >/dev/null ||
    fail "Collector changed the synthetic counts, timestamps, status, or token totals."
}

assert_private_markers_absent() {
  local name=$1 output=$2 markers
  markers=$(jq -r -s '[.. | strings | scan("synthetic-private-[a-z-]+|4111[ -]?1111[ -]?1111[ -]?1111|cvv=987|cvc=654")]
    | unique | length' "$output")
  [[ $markers -gt 0 ]] || return 0
  printf '%s retained %s forbidden synthetic markers.\n' "$name" "$markers" >&2
  failures=$((failures + 1))
}

prepare_fixture() {
  local name=$1 fixture=$2
  mkdir -p "$fixture"
  jq -c -f "$collector_test_dir/privacy-fixtures.jq" "$collector_test_dir/status-message.json" >"$fixture/input.json"
  write_collector_config "$name" >"$fixture/config.yaml"
}

test_privacy() {
  local name=$1 fixture="$test_root/$1"
  prepare_fixture "$name" "$fixture"
  start_collector "$fixture"
  wait_for_export "$fixture/output.json"
  stop_collector
  assert_signals "$fixture/output.json"
  assert_private_markers_absent "$name" "$fixture/output.json"
}

test_default_pattern() {
  local fixture="$test_root/default-pattern"
  prepare_fixture edge "$fixture"
  jq -c 'walk(if type == "string" and
    (. == "synthetic-private-email@example.invalid" or . == "synthetic-private-address (Unit 3)")
    then "unlisted@example.invalid" else . end)' "$fixture/input.json" >"$fixture/default.json"
  mv "$fixture/default.json" "$fixture/input.json"
  start_collector "$fixture" ""
  wait_for_export "$fixture/output.json"
  stop_collector
  assert_signals "$fixture/output.json"
  assert_private_markers_absent default "$fixture/output.json"
  jq -e -s 'any(.. | strings; . == "unlisted@example.invalid")' "$fixture/output.json" >/dev/null ||
    fail "An empty personal pattern removed unlisted metadata."
}

test_literal_dollars() {
  local name=$1 fixture="$test_root/$1-dollars"
  # shellcheck disable=SC2016 # Dollar signs are literal regression data.
  local pattern='\Qperson$$tag@example.invalid\E|\Q${env:HNET_TEST_LITERAL}\E'
  prepare_fixture "$name" "$fixture"
  jq -c 'walk(if type == "object" then
    if .key == "originator" then .value.stringValue = "person$$tag@example.invalid"
    elif .key == "session_source" then .value.stringValue = "person$tag@example.invalid"
    elif .key == "auth_mode" then .value.stringValue = "${env:HNET_TEST_LITERAL}"
    else . end else . end)' "$fixture/input.json" >"$fixture/dollars.json"
  mv "$fixture/dollars.json" "$fixture/input.json"
  start_collector "$fixture" "$pattern"
  wait_for_export "$fixture/output.json"
  stop_collector
  jq -e -s '[.. | objects | select(.key == "originator" or .key == "auth_mode" or .key == "session_source")]
    | length > 0 and all(.value.stringValue ==
      (if .key == "session_source" then "person$tag@example.invalid" else "****" end))' \
    "$fixture/output.json" >/dev/null || fail "$name changed literal dollar matches."
}

inject_transform_error() {
  awk '
    /context: scope/ { scope = 1 }
    { print }
    scope && /statements:/ {
      print "          - set(scope.attributes[\"failure\"], ParseJSON(scope.name)) where scope.name == \"synthetic-transform-failure\""
      scope = 0
    }
  ' "$1" >"$1.injected"
  mv "$1.injected" "$1"
}

wait_for_transform_errors() {
  local attempt count
  for ((attempt = 0; attempt < 100; attempt++)); do
    count=$(docker logs "$container_id" 2>&1 | grep -c 'failed to execute statement' || true)
    [[ $count -lt 3 ]] || return 0
    sleep 0.1
  done
  fail "Collector did not exercise a transform error for all three signals."
}

test_transform_failure() {
  local name=$1 fixture="$test_root/$1-failure"
  prepare_fixture "$name" "$fixture"
  inject_transform_error "$fixture/config.yaml"
  jq -c 'walk(if type == "object" and has("scope") then
    .scope.name = "synthetic-transform-failure" else . end)' "$fixture/input.json" >"$fixture/rejected.json"
  cat "$fixture/rejected.json" >>"$fixture/input.json"
  start_collector "$fixture"
  wait_for_export "$fixture/output.json"
  wait_for_transform_errors
  stop_collector
  assert_signals "$fixture/output.json"
  jq -e -s 'all(.. | strings; . != "synthetic-transform-failure")' "$fixture/output.json" >/dev/null ||
    fail "$name exported a payload affected by the injected transform error."
  echo "$name dropped all three payloads on transform errors."
}

write_queue_exporter() {
  local name=$1
  printf 'extensions:\n  file_storage:\n    directory: /test/queue\nexporters:\n  otlphttp:\n    endpoint: http://127.0.0.1:4318\n'
  # Exercise each real queue/retry policy with an isolated OTLP sink.
  awk '
    /^    sending_queue:/ { copying = 1 }
    copying && /^service:/ { exit }
    copying { print }
  ' "$repo_dir/ops/telemetry/collector/$name.yaml"
}

write_queue_config() {
  local name=$1 fixture=$2
  awk '/^exporters:/ { exit } { print }' "$fixture/config.yaml"
  write_queue_exporter "$name"
  awk '
    /^service:/ { copying = 1; print; print "  extensions: [file_storage]"; next }
    copying { sub(/exporters: \[file\]/, "exporters: [otlphttp]"); print }
  ' "$fixture/config.yaml"
}

write_sink_config() {
  cat <<'CONFIG'
receivers:
  otlp:
    protocols:
      http:
        endpoint: 127.0.0.1:4318
exporters:
  file:
    path: /test/output.json
    flush_interval: 100ms
service:
  telemetry:
    metrics:
      level: none
  pipelines:
    traces: {receivers: [otlp], exporters: [file]}
    logs: {receivers: [otlp], exporters: [file]}
    metrics: {receivers: [otlp], exporters: [file]}
CONFIG
}

wait_for_outage() {
  local attempt signal observed
  for ((attempt = 0; attempt < 300; attempt++)); do
    observed=0
    docker logs "$container_id" >"$test_root/queue-log" 2>&1
    for signal in traces logs metrics; do
      if grep 'Exporting failed. Will retry' "$test_root/queue-log" |
        grep -Eq "\"otelcol.signal\": *\"$signal\""; then
        observed=$((observed + 1))
      fi
    done
    [[ $observed -lt 3 ]] || return 0
    sleep 0.1
  done
  fail "Collector did not queue all three signals during the synthetic outage."
}

assert_queue_sanitized() {
  local name=$1 directory=$2 result=0
  grep -aRE 'synthetic-private-|4111[ -]?1111[ -]?1111[ -]?1111|cvv=987|cvc=654' "$directory" >/dev/null || result=$?
  [[ $result -le 1 ]] || fail "$name queue privacy scan failed."
  [[ $result -eq 0 ]] || return 0
  echo "$name persisted forbidden synthetic markers before replay." >&2
  failures=$((failures + 1))
}

restart_with_sink() {
  local fixture=$1
  docker kill --signal KILL "$container_id" >/dev/null
  # Prevent fixture re-ingestion: only the durable queue can supply replay.
  : >"$fixture/input.json"
  docker start "$container_id" >/dev/null
  sink_container_id=$(docker run --detach --network "container:$container_id" \
    --read-only --cap-drop ALL --security-opt no-new-privileges \
    --user "$(id -u):$(id -g)" --mount "type=bind,src=$fixture,dst=/test" \
    "$image" --config=/test/sink.yaml)
}

prepare_queue_fixture() {
  local name=$1 fixture=$2
  prepare_fixture "$name" "$fixture"
  mkdir -p "$fixture/queue"
  write_queue_config "$name" "$fixture" >"$fixture/queue.yaml"
  mv "$fixture/queue.yaml" "$fixture/config.yaml"
  write_sink_config >"$fixture/sink.yaml"
}

test_queue_replay() {
  local name=$1 fixture="$test_root/$1-queue"
  prepare_queue_fixture "$name" "$fixture"
  start_collector "$fixture"
  wait_for_outage
  assert_queue_sanitized "$name" "$fixture/queue"
  restart_with_sink "$fixture"
  wait_for_export "$fixture/output.json"
  stop_collector
  container_id=$sink_container_id
  stop_collector
  sink_container_id=
  assert_signals "$fixture/output.json"
  assert_private_markers_absent "$name replay" "$fixture/output.json"
}

test_privacy edge
test_privacy gateway
test_privacy combined
test_default_pattern
test_literal_dollars edge
test_literal_dollars gateway
test_literal_dollars combined
test_transform_failure edge
test_transform_failure gateway
test_queue_replay edge
test_queue_replay gateway
[[ $failures -eq 0 ]] || fail "Collector privacy gate failed ($failures cases)."
echo "Collector privacy tests passed."
