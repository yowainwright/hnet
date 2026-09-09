#!/usr/bin/env bash

set -euo pipefail

script_path=${BASH_SOURCE[0]}
script_parent=${script_path%/*}
script_dir=$(cd -- "$script_parent" && pwd)
# shellcheck source=tests/ops/test_support.sh
source "$script_dir/../../test_support.sh"

test_zsh_client_sends_authenticated_otlp() {
  local fake_bin="$test_root/bin/zsh-client"
  local args_log="$test_root/curl-args.log"
  local config_log="$test_root/curl-config.log"
  mkdir -p "$fake_bin"

  cat >"$fake_bin/curl" <<'TOOL'
#!/bin/sh
printf '%s\n' "$@" >"${OPS_TEST_CURL_ARGS:?}"
cat >"${OPS_TEST_CURL_CONFIG:?}"
touch "$OPS_TEST_CURL_ARGS.done"
TOOL
  chmod +x "$fake_bin/curl"

  PATH="$fake_bin:$PATH" \
    AGENT_TELEMETRY_INGEST_TOKEN=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    OPS_TEST_CURL_ARGS="$args_log" \
    OPS_TEST_CURL_CONFIG="$config_log" \
    zsh -f -c '
      unsetopt bgnice
      source "$1"
      _agent_telemetry_preexec "git secret-command --token hidden"
      _agent_telemetry_precmd
      for attempt in {1..200}; do
        [[ -f "$OPS_TEST_CURL_ARGS.done" ]] && break
        sleep 0.01
      done
      [[ -f "$OPS_TEST_CURL_ARGS.done" ]] || exit 1
    ' zsh "$repo_dir/ops/clients/zsh/agent-telemetry.zsh"

  local args config
  args=$(<"$args_log")
  config=$(<"$config_log")
  assert_contains "$args" 'shell.command.category'
  assert_contains "$args" 'git'
  if [[ $args == *secret-command* || $args == *hidden* ]]; then
    fail "Zsh telemetry included command text."
  fi
  assert_contains "$config" 'Authorization: Bearer aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
}

test_zsh_sender_is_bounded_and_does_not_block() {
  OPS_TEST_SEND_ROOT="$test_root" zsh -f -c '
    unsetopt bgnice
    source "$1"
    _agent_telemetry_send() {
      print -r -- "$_AGENT_TELEMETRY_CATEGORY:$2" >> "$OPS_TEST_SEND_ROOT/sends"
      for attempt in {1..200}; do
        [[ -f "$OPS_TEST_SEND_ROOT/release" ]] && return 0
        sleep 0.01
      done
      touch "$OPS_TEST_SEND_ROOT/timed-out"
    }
    wait_for_sender() {
      for attempt in {1..200}; do
        kill -0 "$_AGENT_TELEMETRY_SENDER_PID" 2>/dev/null || return 0
        sleep 0.01
      done
      return 1
    }
    _agent_telemetry_preexec git
    () { return 7; }
    _agent_telemetry_precmd
    sender=$_AGENT_TELEMETRY_SENDER_PID
    [[ ! -f "$OPS_TEST_SEND_ROOT/timed-out" ]] || exit 1
    for attempt in {1..10}; do
      _agent_telemetry_preexec npm
      _agent_telemetry_precmd
      [[ $_AGENT_TELEMETRY_SENDER_PID == $sender ]] || exit 1
    done
    touch "$OPS_TEST_SEND_ROOT/release"
    wait_for_sender || exit 1
    [[ $(<"$OPS_TEST_SEND_ROOT/sends") == "git:7" ]] || exit 1
    _agent_telemetry_preexec go
    _agent_telemetry_precmd
    wait_for_sender || exit 1
    [[ $(wc -l < "$OPS_TEST_SEND_ROOT/sends") -eq 2 ]] || exit 1
    [[ ! -f "$OPS_TEST_SEND_ROOT/timed-out" ]] || exit 1
  ' zsh "$repo_dir/ops/clients/zsh/agent-telemetry.zsh"
}

make_fake_tools
test_zsh_client_sends_authenticated_otlp
test_zsh_sender_is_bounded_and_does_not_block

echo "zsh telemetry tests passed."
