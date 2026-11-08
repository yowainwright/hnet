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
  brew) touch "${HNET_TEST_DEPS_INSTALLED:?}" ;;
  open) return 1 ;;
  pgrep) return 1 ;;
  esac
}

fake_docker() {
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
  case "${1:-}" in
  --version) echo 2.39.0 ;;
  read) cat "${HNET_TEST_TOKEN_FILE:?}" ;;
  esac
}

main "$@"
