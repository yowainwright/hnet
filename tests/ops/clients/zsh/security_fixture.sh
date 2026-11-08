#!/usr/bin/env bash

set -euo pipefail

main() {
  printf '%s\n' "$@" >>"${HNET_TEST_ARGS:?}"
  case "${1:-}" in
  -i) store_token ;;
  find-generic-password) read_token "$@" ;;
  *) return 2 ;;
  esac
}

store_token() {
  [[ ${HNET_TEST_FAIL_STORE:-0} != 1 ]] || return 1
  local input token
  IFS= read -r input
  token=$(printf '%s' "$input" | awk '{for (i=1;i<NF;i++) if ($i=="-w") {print $(i+1); exit}}')
  [[ -n $token ]] || return 1
  printf '%s' "$token" >"${HNET_TEST_STORE:?}"
}

read_token() {
  [[ ${HNET_TEST_LOCKED:-0} != 1 ]] || return 36
  [[ -f ${HNET_TEST_STORE:?} ]] || return 44
  [[ " $* " != *' -w '* ]] || cat "$HNET_TEST_STORE"
}

main "$@"
