#!/usr/bin/env bash

set -euo pipefail

main() {
  local installer_dir client_operation=client-install
  installer_dir=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)
  if [[ ${1:-} == --check ]]; then
    client_operation=client-check
    shift
  fi
  exec "$installer_dir/ops/apps/hnetctl/hnetctl" "$client_operation" "$@"
}

main "$@"
