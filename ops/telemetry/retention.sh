#!/usr/bin/env bash

set -euo pipefail

main() {
  umask 077
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
  [[ $mode != --dry-run ]] || printf 'Selected snapshot: %s\n' "${ids[@]}"
  apply_retention "$mode" "${ids[@]}"
}

expired_snapshots() {
  local script_dir
  script_dir=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)
  retention_restic snapshots --json --tag agent-telemetry |
    jq --argjson now "$(date -u +%s)" --argjson days "${1:?}" -f "$script_dir/snapshot-retention.jq"
}

apply_retention() {
  local mode=${1:?}
  shift
  if [[ $mode == --dry-run ]]; then
    retention_restic forget --dry-run "$@" >/dev/null || fail "Restic retention dry run failed."
    return
  fi
  retention_restic forget --prune "$@" >/dev/null || fail "Restic forget/prune failed; inspect the repository privately."
  retention_restic check >/dev/null || fail "Post-retention repository check failed."
}

retention_restic() {
  local output status=0 category
  output=$(restic "$@" 2>&1) || status=$?
  if [[ $status == 0 ]]; then
    printf '%s\n' "$output"
    return
  fi
  category=$(retention_error_category "$status" "$output")
  retention_diagnostic "${1:?}" "$status" "$category"
  printf 'Restic %s failed: exit %s, category %s.\n' "$1" "$status" "$category" >&2
  return "$status"
}

retention_error_category() {
  local category
  category=$(retention_status_category "${1:?}")
  if [[ -n $category ]]; then
    echo "$category"
    return
  fi
  case "${2:-}" in
  *[Cc]onnection* | *[Tt]imeout* | *[Nn]etwork* | *'no such host'*) echo connectivity ;;
  *[Cc]orrupt* | *[Dd]amaged* | *[Ii]ntegrity* | *[Cc]hecksum*) echo integrity ;;
  *) echo command-failed ;;
  esac
}

retention_status_category() {
  case "${1:?}" in
  10)
    echo repository-missing
    return
    ;;
  11)
    echo repository-locked
    return
    ;;
  12)
    echo authentication
    return
    ;;
  130)
    echo cancelled
    return
    ;;
  esac
}

retention_diagnostic() {
  local directory="${HNET_CLIENT_HOME:-$HOME/.local/share/hnet}/logs/retention" log
  mkdir -p "$directory" 2>/dev/null || return 0
  log=$(mktemp "$directory/diagnostic.XXXXXX" 2>/dev/null) || return 0
  printf 'operation=%s\nexit_code=%s\ncategory=%s\n' "${1:?}" "${2:?}" "${3:?}" 2>/dev/null >"$log" || return 0
  echo "Sanitized diagnostic saved in the hnet retention log directory." >&2
}

fail() {
  echo "${1:?}" >&2
  exit 1
}

main "$@"
