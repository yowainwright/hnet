#!/usr/bin/env bash

set -Eeuo pipefail

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
      _agent_telemetry_preexec git
      record=$(_agent_telemetry_record 12 7)
      _agent_telemetry_send "$record" "$record"
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
  awk '/^--data-binary$/ { getline; print }' "$args_log" |
    jq -e '.resourceLogs[0].scopeLogs[0].logRecords | length == 2' >/dev/null
}

test_zsh_sender_is_bounded_and_does_not_block() {
  OPS_TEST_SEND_ROOT="$test_root" zsh -f -c '
    unsetopt bgnice
    zmodload zsh/zselect
    source "$1"
    _agent_telemetry_send() {
      print -rl -- "$@" >> "$OPS_TEST_SEND_ROOT/sends"
      for attempt in {1..200}; do
        [[ -f "$OPS_TEST_SEND_ROOT/release" ]] && return 0
        sleep 0.01
      done
      touch "$OPS_TEST_SEND_ROOT/timed-out"
    }
    wait_for_sender() {
      for attempt in {1..200}; do
        (( _AGENT_TELEMETRY_SENDER_FD >= 0 )) || return 0
        if zselect -r "$_AGENT_TELEMETRY_SENDER_FD" -t 1; then
          _agent_telemetry_sender_done "$_AGENT_TELEMETRY_SENDER_FD"
        fi
      done
      return 1
    }
    _agent_telemetry_preexec git
    () { return 7; }
    _agent_telemetry_precmd
    sender=$_AGENT_TELEMETRY_SENDER_FD
    [[ ! -f "$OPS_TEST_SEND_ROOT/timed-out" ]] || exit 1
    for attempt in {1..10}; do
      _agent_telemetry_preexec npm
      _agent_telemetry_precmd
      [[ $_AGENT_TELEMETRY_SENDER_FD == $sender ]] || exit 1
    done
    [[ ${#_AGENT_TELEMETRY_PENDING} -eq 10 ]] || exit 1
    touch "$OPS_TEST_SEND_ROOT/release"
    wait_for_sender || exit 1
    [[ $(wc -l < "$OPS_TEST_SEND_ROOT/sends") -eq 11 ]] || exit 1
    _agent_telemetry_preexec go
    _agent_telemetry_precmd
    wait_for_sender || exit 1
    [[ $(wc -l < "$OPS_TEST_SEND_ROOT/sends") -eq 12 ]] || exit 1
    [[ ! -f "$OPS_TEST_SEND_ROOT/timed-out" ]] || exit 1
  ' zsh "$repo_dir/ops/clients/zsh/agent-telemetry.zsh"
  jq -e -s 'map(.attributes | map({key, value: (.value | .[])}) | from_entries)
    | .[0]["shell.command.category"] == "git" and .[0]["shell.exit_code"] == "7" and
      (.[1:11] | all(.["shell.command.category"] == "npm" and .["shell.exit_code"] == "0")) and
      .[11]["shell.command.category"] == "go"' "$test_root/sends" >/dev/null
}

test_zsh_drains_pending_events_while_idle() {
  local fixture="$test_root/idle.zsh"
  cat >"$fixture" <<'ZSH'
source "$OPS_TEST_CLIENT"
add-zsh-hook -d preexec _agent_telemetry_preexec
add-zsh-hook -d precmd _agent_telemetry_precmd
_agent_telemetry_send() {
  for attempt in {1..500}; do
    if [[ -f "$OPS_TEST_SEND_ROOT/idle-release" ]]; then
      print -rl -- "$@" >> "$OPS_TEST_SEND_ROOT/idle-sends"
      return 0
    fi
    sleep 0.01
  done
}
_agent_telemetry_preexec git
_agent_telemetry_precmd
_agent_telemetry_preexec npm
_agent_telemetry_precmd
touch "$OPS_TEST_SEND_ROOT/idle-ready"
input=
vared input
ZSH
  OPS_TEST_SEND_ROOT="$test_root" OPS_TEST_ZLE_FIXTURE="$fixture" \
    OPS_TEST_CLIENT="$repo_dir/ops/clients/zsh/agent-telemetry.zsh" zsh -f -c '
      zmodload zsh/zpty
      zpty -b telemetry "zsh -fi \"\$OPS_TEST_ZLE_FIXTURE\""
      {
        for attempt in {1..500}; do
          [[ -f "$OPS_TEST_SEND_ROOT/idle-ready" ]] && break
          sleep 0.01
        done
        [[ -f "$OPS_TEST_SEND_ROOT/idle-ready" ]] || { print -u2 "Idle shell did not start."; exit 1; }
        touch "$OPS_TEST_SEND_ROOT/idle-release"
        for attempt in {1..500}; do
          if [[ -f "$OPS_TEST_SEND_ROOT/idle-sends" ]] &&
              [[ $(wc -l < "$OPS_TEST_SEND_ROOT/idle-sends") -eq 2 ]]; then
            exit 0
          fi
          sleep 0.01
        done
        print -u2 "Idle shell did not drain its pending event."
        exit 1
      } always {
        zpty -d telemetry
      }
    '
}

trap 'echo "Zsh telemetry test failed at line $LINENO." >&2' ERR
make_fake_tools
test_zsh_client_sends_authenticated_otlp
test_zsh_sender_is_bounded_and_does_not_block
test_zsh_drains_pending_events_while_idle

echo "zsh telemetry tests passed."
