#!/usr/bin/env bash

set -euo pipefail

script_path=${BASH_SOURCE[0]}
script_parent=${script_path%/*}
script_dir=$(cd -- "$script_parent" && pwd)
backup_name=${1:-}

fail() {
  echo "$1" >&2
  exit "${2:-1}"
}

[[ $backup_name =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail "Pass a valid backup name."
[[ -n ${RESTIC_REPOSITORY:-} ]] || fail "RESTIC_REPOSITORY is required."

has_password=${RESTIC_PASSWORD:+yes}
has_password_file=${RESTIC_PASSWORD_FILE:+yes}
has_password_command=${RESTIC_PASSWORD_COMMAND:+yes}
[[ -n $has_password || -n $has_password_file || -n $has_password_command ]] || fail "A restic password source is required."

command -v restic >/dev/null 2>&1 || fail "Missing required command: restic"

backup_path="${HNET_BACKUP_DIR:-$script_dir/backups}/$backup_name"
[[ -d $backup_path && ! -L $backup_path ]] || fail "Backup does not exist: $backup_name"

restic backup --tag agent-telemetry -- "$backup_path"
