#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
env_file=${TELEMETRY_STUDIO_ENV:-"$script_dir/.env.mac-studio"}
backup_name=${1:-"telemetry-$(date -u +%Y%m%dT%H%M%SZ)"}

if [[ ! $backup_name =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
  echo "Backup name may contain only letters, numbers, dots, underscores, and dashes." >&2
  exit 2
fi

query="BACKUP DATABASE otel TO Disk('telemetry_backups', '${backup_name}')"

docker compose \
  --env-file "$env_file" \
  -f "$script_dir/compose.mac-studio.yml" \
  exec -T \
  -e BACKUP_QUERY="$query" \
  clickhouse \
  sh -c 'clickhouse-client --user "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" --query "$BACKUP_QUERY"'

echo "$script_dir/backups/$backup_name"
