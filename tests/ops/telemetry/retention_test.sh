#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=tests/ops/test_support.sh
source "${BASH_SOURCE[0]%/*}/../test_support.sh"

main() {
  export RESTIC_REPOSITORY="$test_root/restic" RESTIC_PASSWORD=synthetic-restic-test-password
  export RESTIC_CACHE_DIR="$test_root/cache"
  mkdir -p "$test_root/input"
  printf 'synthetic-restore-marker\n' >"$test_root/input/marker"
  restic init >/dev/null
  restic backup --tag agent-telemetry --time '2020-01-01 00:00:00' "$test_root/input" >/dev/null
  restic backup --tag other-app --time '2020-01-01 00:00:00' "$test_root/input" >/dev/null
  restic backup --tag agent-telemetry "$test_root/input" >/dev/null
  test_dry_run_and_apply
  test_old_newest_snapshot_expires
  echo "Configurable snapshot expiration, dry run, scoped pruning and restore tests passed."
}

test_dry_run_and_apply() {
  local before after output
  before=$(restic snapshots --json | jq length)
  output=$("$repo_dir/ops/telemetry/retention.sh")
  [[ $output == *'Expired hnet snapshots: 1;'* ]] || fail "Wall-clock selection failed: $output"
  after=$(restic snapshots --json | jq length)
  [[ $before == "$after" ]] || fail "Dry run changed snapshots."
  "$repo_dir/ops/telemetry/retention.sh" --apply
  [[ $(restic snapshots --json | jq length) == 2 ]] || fail "Retention removed the wrong snapshots."
  restic restore latest --tag agent-telemetry --target "$test_root/restore" >/dev/null
  cmp "$test_root/input/marker" "$test_root/restore$test_root/input/marker" || fail "Retained snapshot did not restore."
  if BACKUP_RETENTION_DAYS=0 "$repo_dir/ops/telemetry/retention.sh" >/dev/null 2>&1; then
    fail "Invalid retention policy accepted."
  fi
}

test_old_newest_snapshot_expires() {
  export RESTIC_REPOSITORY="$test_root/stopped-backups"
  restic init >/dev/null
  restic backup --tag agent-telemetry --time '2020-01-01 00:00:00' "$test_root/input" >/dev/null
  local output
  output=$(BACKUP_RETENTION_DAYS=7 "$repo_dir/ops/telemetry/retention.sh")
  [[ $output == *'Expired hnet snapshots: 1; policy: 7 days;'* ]] || fail "A stale newest snapshot escaped expiry."
}

main
