#!/usr/bin/env bash

set -euo pipefail

: "${CLICKHOUSE_PASSWORD:?CLICKHOUSE_PASSWORD is required}"

readonly client=(
  clickhouse-client
  --host clickhouse
  --user otel_collector
  --password "${CLICKHOUSE_PASSWORD}"
)

readonly required_tables=(otel_logs otel_traces otel_metrics_histogram)
readonly max_attempts=150

tables_exist() {
  local table
  for table in "${required_tables[@]}"; do
    "${client[@]}" --query "DESCRIBE TABLE otel.${table}" >/dev/null 2>&1 || return 1
  done
}

attempt=0
until tables_exist; do
  attempt=$((attempt + 1))
  if ((attempt % 30 == 0)); then
    echo "Waiting for the first logs, traces, and histogram metrics"
  fi
  if ((attempt >= max_attempts)); then
    echo "Timed out waiting for OpenTelemetry tables" >&2
    exit 1
  fi
  sleep 2
done

"${client[@]}" --multiquery </bootstrap/dashboard-views.sql
