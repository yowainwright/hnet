#!/usr/bin/env bash

set -euo pipefail

main() {
  local tool=${0##*/}
  printf '%s %s\n' "$tool" "$*" >>"${HNET_TEST_TOOL_LOG:?}"
  case "$tool" in
  uname) echo Darwin ;;
  docker) fake_docker "$@" ;;
  tailscale) printf '{"BackendState":"%s"}\n' "${HNET_TEST_TAILSCALE_STATE:-Running}" ;;
  plutil) sed -n 's/.*"BackendState":"\([^"]*\)".*/\1/p' ;;
  codex) fake_codex "$@" ;;
  op) fake_op "$@" ;;
  curl) fake_client_curl "$@" ;;
  brew) touch "${HNET_TEST_DEPS_INSTALLED:?}" ;;
  open) return 1 ;;
  pgrep) return 1 ;;
  esac
}

fake_docker() {
  if [[ -n ${HNET_TEST_RENDERED:-} ]]; then
    fake_client_docker "$@"
    return
  fi
  case "${1:-}" in
  context) printf '%s\n' "${HNET_TEST_DOCKER_ENDPOINT:-unix:///fixture/docker.sock}" ;;
  info) return "${HNET_TEST_DOCKER_DOWN:-0}" ;;
  ps) echo aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa ;;
  inspect) echo healthy ;;
  esac
}

fake_codex() {
  fake_codex_installed || return 127
  fake_codex_logged_in "$@" || return 1
}

fake_codex_installed() {
  [[ ${HNET_TEST_MISSING:-} != codex ]] && return 0
  [[ -e ${HNET_TEST_DEPS_INSTALLED:?} ]]
}

fake_codex_logged_in() {
  [[ ${1:-} != login ]] && return 0
  [[ ${HNET_TEST_LOGGED_OUT:-0} != 1 ]]
}

fake_op() {
  if [[ -n ${HNET_TEST_REGISTRY:-} ]]; then
    fake_managed_op "$@"
    return
  fi
  case "${1:-}" in
  --version) echo 2.39.0 ;;
  read) cat "${HNET_TEST_TOKEN_FILE:?}" ;;
  esac
}

fake_client_docker() {
  local previous='' argument
  for argument in "$@"; do
    if [[ $previous == -f ]]; then
      capture_client_overlay "$argument"
    fi
    previous=$argument
  done
  case " $* " in
  *' up '*) [[ ${HNET_TEST_APPLY_FAIL:-0} == 0 ]] ;;
  esac
}

capture_client_overlay() {
  local file=${1:?}
  jq -e '.services.collector.ports' "$file" >/dev/null 2>&1 || return 0
  cp "$file" "$HNET_TEST_RENDERED"
}

fake_managed_op() {
  local value
  case "${1:-} ${2:-}" in
  'item list')
    [[ ${HNET_TEST_OP_FAIL:-0} == 0 ]] || return 1
    cat "$HNET_TEST_REGISTRY"
    ;;
  'item create') fake_client_item_create "$@" ;;
  'item get')
    value=$(printf '%064d' 5)
    jq -n --arg value "$value" '{category:"PASSWORD",fields:[{id:"password",value:$value}]}'
    ;;
  *) fake_client_token "${2:-}" ;;
  esac
}

fake_client_item_create() {
  local title=
  while [[ $# -gt 0 ]]; do
    [[ $1 != --title ]] || title=${2:?}
    shift
  done
  jq --arg title "$title" '. + [{id: ("item-" + $title), title: $title, tags: ["hnet-client"]}]' \
    "$HNET_TEST_REGISTRY" >"$HNET_TEST_REGISTRY.pending"
  mv "$HNET_TEST_REGISTRY.pending" "$HNET_TEST_REGISTRY"
  jq '.[-1]' "$HNET_TEST_REGISTRY"
}

fake_client_token() {
  case "${1:-}" in
  *clickhouse-writer-password) printf '%064d' 2 ;;
  *clickhouse-reader-password) printf '%064d' 3 ;;
  *central-token) printf '%064d' 4 ;;
  *item-hnet-client-build-agent/password) printf '%064d' 6 ;;
  */password) printf '%064d' 5 ;;
  *) printf '%064d' 1 ;;
  esac
}

fake_client_curl() {
  case " $* " in
  *' --config - '*) cat >/dev/null ;;
  esac
  printf 200
}

main "$@"
