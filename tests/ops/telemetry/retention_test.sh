#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=tests/ops/test_support.sh
source "${BASH_SOURCE[0]%/*}/../test_support.sh"

main() {
  export RESTIC_REPOSITORY="$test_root/restic" RESTIC_PASSWORD=synthetic-restic-test-password
  export RESTIC_CACHE_DIR="$test_root/cache"
  export HNET_CLIENT_HOME="$test_root/state"
  mkdir -p "$test_root/input"
  printf 'synthetic-restore-marker\n' >"$test_root/input/marker"
  restic init >/dev/null
  restic backup --tag agent-telemetry --time '2020-01-01 00:00:00' "$test_root/input" >/dev/null
  restic backup --tag other-app --time '2020-01-01 00:00:00' "$test_root/input" >/dev/null
  restic backup --tag agent-telemetry "$test_root/input" >/dev/null
  test_dry_run_and_apply
  test_old_newest_snapshot_expires
  test_failure_diagnostics_are_private
  echo "Configurable snapshot expiration, dry run, scoped pruning and restore tests passed."
}

test_dry_run_and_apply() {
  local before after output
  before=$(restic snapshots --json | jq length)
  output=$("$repo_dir/ops/telemetry/retention.sh")
  [[ $output == *'Expired hnet snapshots: 1;'* ]] || fail "Wall-clock selection failed: $output"
  local selected
  selected=$(restic snapshots --json | jq -r '.[] | select(.time | startswith("2020")) | select(.tags | index("agent-telemetry")) | .id')
  [[ $output == *"Selected snapshot: $selected"* ]] || fail "Dry run hid the selected snapshot ID."
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

test_failure_diagnostics_are_private() {
  write_failing_restic
  assert_restic_failure 11 repository-locked 'connection refused'
  assert_restic_failure 1 connectivity 'connection refused'
  assert_restic_failure 1 integrity 'checksum mismatch'
  local directory="$HNET_CLIENT_HOME/logs/retention" diagnostic
  diagnostic=$(find "$directory" -type f -name 'diagnostic.*' -print -quit)
  grep -Fq 'category=' "$diagnostic" || fail "Sanitized diagnostic was not retained."
  ! grep -RFq synthetic-sensitive-marker "$directory" || fail "Raw Restic output was logged."
  [[ -z $(find "$directory" -type f ! -perm 600 -print -quit) ]] || fail "Diagnostic files are not private."
}

write_failing_restic() {
  mkdir -p "$test_root/bin"
  cat >"$test_root/bin/restic" <<'TOOL'
#!/bin/sh
printf 'synthetic-sensitive-marker: %s\n' "$HNET_TEST_RESTIC_MESSAGE" >&2
exit "$HNET_TEST_RESTIC_EXIT"
TOOL
  chmod +x "$test_root/bin/restic"
}

assert_restic_failure() {
  local status=${1:?} category=${2:?} message=${3:?} output
  if output=$(PATH="$test_root/bin:$PATH" HNET_TEST_RESTIC_EXIT="$status" HNET_TEST_RESTIC_MESSAGE="$message" \
    "$repo_dir/ops/telemetry/retention.sh" 2>&1); then
    fail "Failed Restic command was accepted."
  fi
  [[ $output == *"exit $status, category $category"* ]] || fail "Restic error classification is missing."
  [[ $output != *synthetic-sensitive-marker* ]] || fail "Raw Restic output escaped to the terminal."
}

main
