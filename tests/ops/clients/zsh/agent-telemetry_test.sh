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
TOOL
  chmod +x "$fake_bin/curl"

  PATH="$fake_bin:$PATH" \
    AGENT_TELEMETRY_INGEST_TOKEN=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
    OPS_TEST_CURL_ARGS="$args_log" \
    OPS_TEST_CURL_CONFIG="$config_log" \
    zsh -f -c '
      source "$1"
      _agent_telemetry_preexec "git secret-command --token hidden"
      _agent_telemetry_precmd
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

make_fake_tools
test_zsh_client_sends_authenticated_otlp

echo "zsh telemetry tests passed."
