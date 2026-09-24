#!/usr/bin/env bash

set -euo pipefail

views_file=ops/telemetry/clickhouse/dashboard-views.sql
dashboard_file=ops/telemetry/grafana/dashboards/agent-telemetry.json
values_file=ops/telemetry/values.yaml

fail() {
  echo "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

expand_grafana_macros() {
  perl -0pe 's/\$__timeFilter\(([^()]+)\)/(($1 >= toDateTime64('\''2026-01-01 00:00:00'\'', 9)) AND ($1 <= toDateTime64('\''2026-01-01 01:00:00'\'', 9)))/g'
}

clickhouse_image() {
  awk '$1 == "clickhouse:" { print $2 }' "$values_file"
}

verify_dashboard_queries_execute() {
  local image raw_sql expanded_sql panel=0
  require_command docker
  image=$(clickhouse_image)
  [[ -n $image ]] || fail "ClickHouse image is missing from $values_file."
  while IFS= read -r -d '' raw_sql; do
    panel=$((panel + 1))
    expanded_sql=$(printf '%s' "$raw_sql" | expand_grafana_macros)
    docker run --rm "$image" clickhouse-local --query "EXPLAIN SYNTAX $expanded_sql" >/dev/null ||
      fail "Expanded dashboard query $panel must execute in ClickHouse."
  done < <(jq -j '.panels[].targets[].rawSql + "\u0000"' "$dashboard_file")
}

grep -Fq 'CREATE OR REPLACE VIEW otel.dotfiles_installs' "$views_file" || fail "Dotfiles install view is missing."
grep -Fq "LogAttributes['dotfiles.package'] AS package_name" "$views_file" || fail "Dotfiles package field is missing."
grep -Fq "LogAttributes['dotfiles.manager'] AS manager" "$views_file" || fail "Dotfiles manager field is missing."
grep -Fq "LogAttributes['dotfiles.version'] AS version" "$views_file" || fail "Dotfiles version field is missing."
grep -Fq "LogAttributes['event.name'] = 'dotfiles.npm_global_install'" "$views_file" || fail "Dotfiles install event filter is missing."
grep -Fq 'otel.dotfiles_installs' "$dashboard_file" || fail "Dotfiles dashboard query is missing."
grep -Fq 'Recent dotfiles installs' "$dashboard_file" || fail "Dotfiles dashboard panel is missing."

# Filter individual events before aggregation, including partial five-minute buckets.
jq -e '
  [.panels[].targets[].rawSql] | length == 15 and all(.[];
    contains("$__timeFilter(") and
    (test("FROM otel\\.agent_(sessions|inventory|hosts|calls_5m|tokens_5m)\\b") | not) and
    ((contains("GROUP BY") | not) or test("WHERE[^;]*\\$__timeFilter\\([^)]*\\)[^;]*GROUP BY"))
  )
' "$dashboard_file" >/dev/null || fail "Dashboard queries must filter events within the selected time range."

verify_dashboard_queries_execute

echo "dashboard view tests passed."
