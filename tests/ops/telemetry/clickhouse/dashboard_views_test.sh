#!/usr/bin/env bash

set -euo pipefail

views_file=ops/telemetry/clickhouse/dashboard-views.sql
dashboard_file=${HNET_DASHBOARD_FILE:-ops/telemetry/grafana/dashboards/agent-telemetry.json}
values_file=ops/telemetry/values.yaml
clickhouse_runner=()

main() {
  verify_required_views
  verify_time_filters
  verify_dashboard_queries_execute
  echo "dashboard view tests passed."
}

verify_required_views() {
  grep -Fq 'CREATE OR REPLACE VIEW otel.dotfiles_installs' "$views_file" || fail "Dotfiles install view is missing."
  grep -Fq "LogAttributes['dotfiles.package'] AS package_name" "$views_file" || fail "Dotfiles package field is missing."
  grep -Fq "LogAttributes['dotfiles.manager'] AS manager" "$views_file" || fail "Dotfiles manager field is missing."
  grep -Fq "LogAttributes['dotfiles.version'] AS version" "$views_file" || fail "Dotfiles version field is missing."
  grep -Fq "LogAttributes['event.name'] = 'dotfiles.npm_global_install'" "$views_file" || fail "Dotfiles install event filter is missing."
  grep -Fq 'otel.dotfiles_installs' "$dashboard_file" || fail "Dotfiles dashboard query is missing."
  grep -Fq 'Recent dotfiles installs' "$dashboard_file" || fail "Dotfiles dashboard panel is missing."
}

verify_time_filters() {
  # Filter individual events before aggregation, including partial five-minute buckets.
  jq -e '
    [.panels[].targets[].rawSql] | length == 20 and all(.[];
      contains("$__timeFilter(") and
      (test("FROM otel\\.agent_(sessions|inventory|hosts|calls_5m|tokens_5m)\\b") | not) and
      ((contains("GROUP BY") | not) or test("WHERE[^;]*\\$__timeFilter\\([^)]*\\)[^;]*GROUP BY"))
    )
  ' "$dashboard_file" >/dev/null || fail "Dashboard queries must filter events within the selected time range."
}

verify_dashboard_queries_execute() {
  if ! configure_clickhouse_runner; then
    report_missing_runner
    return
  fi
  verify_model_call_events
  verify_usage_accounting
}

report_missing_runner() {
  [[ ${HNET_REQUIRE_DASHBOARD_QUERY_EXECUTION:-0} != 1 ]] ||
    fail "Dashboard checks require ClickHouse or a running local Docker daemon."
  echo "Skipping executable dashboard checks; ClickHouse and local Docker are unavailable." >&2
}

configure_clickhouse_runner() {
  local image
  configure_native_clickhouse && return 0
  command -v docker >/dev/null 2>&1 || return 1
  docker_is_local || fail "Dashboard checks require local Docker."
  docker info >/dev/null 2>&1 || return 1
  image=$(clickhouse_image)
  [[ -n $image ]] || fail "ClickHouse image is missing from $values_file."
  clickhouse_runner=(docker run --rm --network none "$image" clickhouse-local)
}

configure_native_clickhouse() {
  if command -v clickhouse-local >/dev/null 2>&1; then
    clickhouse_runner=(clickhouse-local)
    return 0
  fi
  if command -v clickhouse >/dev/null 2>&1; then
    clickhouse_runner=(clickhouse local)
    return 0
  fi
  return 1
}

docker_is_local() {
  local endpoint
  [[ ${DOCKER_HOST:-unix://local} == unix://* ]] || return 1
  endpoint=$(docker context inspect --format '{{.Endpoints.docker.Host}}') || return 1
  [[ $endpoint == unix://* ]]
}

clickhouse_image() {
  awk '$1 == "clickhouse:" { print $2 }' "$values_file"
}

verify_model_call_events() {
  local predicate result expected
  predicate=$(awk '/CREATE OR REPLACE VIEW otel.agent_calls AS/ {view=1}
    view && /^WHERE/ {predicate=1}
    predicate {line=$0; sub(/;$/, "", line); print line; if (/;$/) exit}' "$views_file")
  result=$("${clickhouse_runner[@]}" --query "
    SELECT event FROM values('event String, operation String',
      ('codex.api_request', ''), ('codex.websocket_request', ''), ('claude_code.api_request', ''),
      ('codex.conversation_starts', ''), ('trace.operation', 'chat'))
    $predicate ORDER BY event FORMAT TSV")
  expected=$'claude_code.api_request\ncodex.api_request\ncodex.websocket_request\ntrace.operation'
  [[ $result == "$expected" ]] || fail "Model calls must include HTTP, WebSocket, and chat operations."
}

verify_usage_accounting() {
  local test_dir=${BASH_SOURCE[0]%/*} fixture_sql views_sql assertions_sql dashboard_sql
  fixture_sql=$(<"$test_dir/usage-fixture.sql")
  views_sql=$(<"$views_file")
  assertions_sql=$(<"$test_dir/usage-assertions.sql")
  dashboard_sql=$(jq -r '.panels[].targets[].rawSql + ";"' "$dashboard_file" | expand_grafana_macros)
  "${clickhouse_runner[@]}" --multiquery --query "$fixture_sql
$views_sql
$assertions_sql
$dashboard_sql" >/dev/null || fail "Model and token accounting failed."
}

expand_grafana_macros() {
  perl -0pe 's/\$__timeFilter\(([^()]+)\)/(($1 >= toDateTime64('\''2026-01-01 00:00:00'\'', 9)) AND ($1 <= toDateTime64('\''2026-01-01 01:00:00'\'', 9)))/g'
}

fail() {
  echo "$1" >&2
  exit 1
}

main
