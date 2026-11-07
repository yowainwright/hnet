#!/usr/bin/env bash

set -euo pipefail

main() {
  local parent prefix
  parent=$(launcher_directory)
  if [[ -d "$parent/ops" ]]; then
    exec "$parent/ops/apps/hnetctl/hnetctl" "$@"
  fi
  prefix=$(package_prefix "$parent")
  export HNET_PACKAGE_ROOT="$prefix/share/hnet"
  export HNET_PACKAGE_ENTRYPOINT="$prefix/bin/hnetctl"
  [[ -f "$HNET_PACKAGE_ROOT/VERSION" ]] || {
    echo "hnet support files are missing; reinstall the package." >&2
    exit 1
  }
  exec "$HNET_PACKAGE_ROOT/ops/apps/hnetctl/hnetctl" "$@"
}

launcher_directory() {
  local entry=${BASH_SOURCE[0]} parent target
  while [[ -L $entry ]]; do
    parent=$(cd -- "${entry%/*}" && pwd)
    target=$(readlink "$entry")
    case "$target" in
    /*) entry=$target ;;
    *) entry="$parent/$target" ;;
    esac
  done
  cd -- "${entry%/*}" && pwd
}

package_prefix() {
  local prefix stable
  prefix=$(cd -- "${1:?}/.." && pwd)
  stable="$(cd -- "$prefix/../../.." && pwd)/opt/hnet"
  if [[ -d "$stable/share/hnet/ops" ]]; then
    printf '%s' "$stable"
    return
  fi
  printf '%s' "$prefix"
}

main "$@"
