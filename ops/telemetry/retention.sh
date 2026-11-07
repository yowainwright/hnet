#!/usr/bin/env bash

set -euo pipefail

main() {
  local mode=${1:---dry-run} days=${BACKUP_RETENTION_DAYS:-30} ids=() id listing
  [[ $# -le 1 && ($mode == --dry-run || $mode == --apply) ]] || fail "Usage: retention.sh [--dry-run|--apply]"
  [[ $days =~ ^[1-9][0-9]{0,4}$ && $days -le 36500 ]] || fail "BACKUP_RETENTION_DAYS must be 1..36500."
  : "${RESTIC_REPOSITORY:?RESTIC_REPOSITORY is required}"
  command -v restic >/dev/null 2>&1 || fail "Restic is required."
  command -v jq >/dev/null 2>&1 || fail "jq is required."
  listing=$(expired_snapshots "$days") || fail "Could not safely select expired snapshots."
  while IFS= read -r id; do
    [[ -z $id ]] || ids+=("$id")
  done < <(printf '%s' "$listing" | jq -r '.[]')
  echo "Expired hnet snapshots: ${#ids[@]}; policy: $days days; mode: $mode."
  [[ ${#ids[@]} -gt 0 ]] || return 0
  apply_retention "$mode" "${ids[@]}"
}

expired_snapshots() {
  local script_dir
  script_dir=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)
  restic snapshots --json --tag agent-telemetry 2>/dev/null |
    jq --argjson now "$(date -u +%s)" --argjson days "${1:?}" -f "$script_dir/snapshot-retention.jq"
}

apply_retention() {
  local mode=${1:?}
  shift
  if [[ $mode == --dry-run ]]; then
    restic forget --dry-run "$@" >/dev/null 2>&1 || fail "Restic retention dry run failed."
    return
  fi
  restic forget --prune "$@" >/dev/null 2>&1 || fail "Restic forget/prune failed; inspect the repository privately."
  restic check >/dev/null 2>&1 || fail "Post-retention repository check failed."
}

fail() {
  echo "${1:?}" >&2
  exit 1
}

main "$@"
