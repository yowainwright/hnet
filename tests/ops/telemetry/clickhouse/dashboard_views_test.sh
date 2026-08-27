#!/usr/bin/env bash

set -euo pipefail

views_file=ops/telemetry/clickhouse/dashboard-views.sql
dashboard_file=ops/telemetry/grafana/dashboards/agent-telemetry.json

fail() {
  echo "$1" >&2
  exit 1
}

grep -Fq 'CREATE OR REPLACE VIEW otel.dotfiles_installs' "$views_file" || fail "Dotfiles install view is missing."
grep -Fq "LogAttributes['dotfiles.package'] AS package_name" "$views_file" || fail "Dotfiles package field is missing."
grep -Fq "LogAttributes['dotfiles.manager'] AS manager" "$views_file" || fail "Dotfiles manager field is missing."
grep -Fq "LogAttributes['dotfiles.version'] AS version" "$views_file" || fail "Dotfiles version field is missing."
grep -Fq "LogAttributes['event.name'] = 'dotfiles.npm_global_install'" "$views_file" || fail "Dotfiles install event filter is missing."
grep -Fq 'otel.dotfiles_installs' "$dashboard_file" || fail "Dotfiles dashboard query is missing."
grep -Fq 'Recent dotfiles installs' "$dashboard_file" || fail "Dotfiles dashboard panel is missing."

echo "dashboard view tests passed."
