#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=tests/ops/test_support.sh
source "${BASH_SOURCE[0]%/*}/../../test_support.sh"

startup_test_dir=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)

main() {
  configure_test_paths
  write_fake_tools
  write_fake_codex
  write_edge_config
  test_enable_is_repeatable_and_keeps_secrets_out_of_startup
  test_codex_enrollment_and_launchers
  test_desktop_requires_a_fresh_process
  test_claude_launcher_disables_content_export
  test_existing_codex_telemetry_is_preserved
  test_changed_exporter_cannot_receive_the_token
  test_failed_keychain_write_does_not_install_startup
  test_fresh_shell_loads_hooks_once
  test_missing_locked_and_invalid_tokens_leave_shell_usable
  test_autoload_does_not_trace_the_token
  echo "Automatic zsh setup tests passed."
}

configure_test_paths() {
  export ZDOTDIR="$test_root/startup"
  export PATH="$test_root/bin:$PATH"
  export TELEMETRY_EDGE_ENV="$test_root/edge.env"
  export HNET_SECURITY_BIN="$test_root/bin/security" HNET_SHELL_KEYCHAIN="$test_root/login.keychain-db"
  export HNET_TEST_STORE="$test_root/keychain-token" HNET_TEST_ARGS="$test_root/keychain-args"
  export HNET_TEST_TOKEN_FILE="$test_root/source-token"
  export HNET_CODEX_CONFIG="$test_root/codex.toml" HNET_TEST_CODEX_ARGS="$test_root/codex-args"
  export HNET_TEST_OTLP_HEADER="$test_root/otlp-header"
  export HNET_TEST_CLAUDE_FLAGS="$test_root/claude-flags"
  unset AGENT_TELEMETRY_INGEST_TOKEN AGENT_TELEMETRY_HOST AGENT_TELEMETRY_UPSTREAM
  unset OTEL_EXPORTER_OTLP_HEADERS
}

write_fake_codex() {
  cat >"$test_root/bin/codex" <<'TOOL'
#!/bin/sh
[ "$1" != app-server ] || exit 0
printf '%s\n' "$@" >"$HNET_TEST_CODEX_ARGS"
printf '%s' "$OTEL_EXPORTER_OTLP_HEADERS" >"$HNET_TEST_OTLP_HEADER"
printf '%s\n' "${CLAUDE_CODE_ENABLE_TELEMETRY:-}" "${OTEL_EXPORTER_OTLP_PROTOCOL:-}" \
  "${OTEL_METRICS_EXPORTER:-}" "${OTEL_LOGS_EXPORTER:-}" \
  "${OTEL_LOG_USER_PROMPTS:-}" "${OTEL_LOG_ASSISTANT_RESPONSES:-}" \
  "${OTEL_LOG_TOOL_DETAILS:-}" "${OTEL_LOG_TOOL_CONTENT:-}" \
  "${OTEL_LOG_RAW_API_BODIES:-}" >"$HNET_TEST_CLAUDE_FLAGS"
TOOL
  cp "$test_root/bin/codex" "$test_root/bin/open"
  cp "$test_root/bin/codex" "$test_root/bin/claude"
  write_fake_pgrep
  chmod +x "$test_root/bin/codex" "$test_root/bin/open" "$test_root/bin/claude"
}

write_fake_pgrep() {
  cat >"$test_root/bin/pgrep" <<'TOOL'
#!/bin/sh
[ "${HNET_TEST_DESKTOP_RUNNING:-0}" = 1 ]
TOOL
  chmod +x "$test_root/bin/pgrep"
}

test_codex_enrollment_and_launchers() {
  "$repo_dir/ops/apps/hnetctl/hnetctl" codex-enable
  "$repo_dir/ops/apps/hnetctl/hnetctl" codex-enable
  [[ $(grep -Fc '# >>> hnet codex >>>' "$HNET_CODEX_CONFIG") == 1 ]] || fail "Duplicate Codex config."
  zsh -fi -c 'source "$1"; codex --version; codex-app; chatgpt-app' \
    zsh "$repo_dir/ops/clients/zsh/auto.zsh"
  local expected
  expected="Authorization=Bearer $(<"$HNET_TEST_STORE")"
  [[ $(<"$HNET_TEST_OTLP_HEADER") == "$expected" ]] || fail "Codex did not receive its header."
  [[ -z ${OTEL_EXPORTER_OTLP_HEADERS:-} ]] || fail "Codex header escaped into the parent shell."
  if grep -Fqf "$HNET_TEST_TOKEN_FILE" "$HNET_CODEX_CONFIG" "$HNET_TEST_CODEX_ARGS"; then
    fail "Codex token appeared in configuration or process arguments."
  fi
}

test_desktop_requires_a_fresh_process() {
  local output
  if output=$(HNET_TEST_DESKTOP_RUNNING=1 HNET_TEST_LOCKED=1 \
    "$repo_dir/ops/apps/hnetctl/hnetctl" chatgpt-app 2>&1); then
    fail "Desktop launcher reused a running app."
  fi
  [[ $output == *'already running'* ]] || fail "Desktop launch did not stop before reading Keychain."
}

test_claude_launcher_disables_content_export() {
  OTEL_LOG_USER_PROMPTS=1 OTEL_LOG_ASSISTANT_RESPONSES=1 OTEL_LOG_TOOL_DETAILS=1 \
    OTEL_LOG_TOOL_CONTENT=1 OTEL_LOG_RAW_API_BODIES=1 \
    zsh -fi -c 'source "$1"; claude --version' zsh "$repo_dir/ops/clients/zsh/auto.zsh"
  local expected
  expected=$'1\nhttp/protobuf\notlp\notlp'
  [[ $(<"$HNET_TEST_CLAUDE_FLAGS") == "$expected" ]] || fail "Claude export flags are unsafe."
  expected="Authorization=Bearer $(<"$HNET_TEST_STORE")"
  [[ $(<"$HNET_TEST_OTLP_HEADER") == "$expected" ]] || fail "Claude did not receive its header."
  [[ -z ${OTEL_EXPORTER_OTLP_HEADERS:-} ]] || fail "Claude header escaped into the parent shell."
  if grep -Fqf "$HNET_TEST_TOKEN_FILE" "$HNET_TEST_CODEX_ARGS"; then
    fail "Claude token appeared in process arguments."
  fi
}

test_existing_codex_telemetry_is_preserved() {
  local alternate="$test_root/existing-codex.toml"
  printf '[otel]\nexporter = "none"\n' >"$alternate"
  if HNET_CODEX_CONFIG="$alternate" "$repo_dir/ops/apps/hnetctl/hnetctl" codex-enable >/dev/null 2>&1; then
    fail "Existing Codex telemetry was overwritten."
  fi
  [[ $(wc -l <"$alternate") -eq 2 ]] || fail "Existing Codex configuration changed."
}

test_changed_exporter_cannot_receive_the_token() {
  local alternate="$test_root/changed-codex.toml"
  sed 's/127.0.0.1/telemetry.example.invalid/g' "$HNET_CODEX_CONFIG" >"$alternate"
  if HNET_CODEX_CONFIG="$alternate" "$repo_dir/ops/apps/hnetctl/hnetctl" codex --version >/dev/null 2>&1; then
    fail "Modified exporter received the hnet authentication environment."
  fi
}

write_fake_tools() {
  mkdir -p "$test_root/bin" "$ZDOTDIR"
  touch "$HNET_SHELL_KEYCHAIN"
  cp "$startup_test_dir/security_fixture.sh" "$HNET_SECURITY_BIN"
  cat >"$test_root/bin/op" <<'TOOL'
#!/bin/sh
cat "$HNET_TEST_TOKEN_FILE"
TOOL
  printf '#!/bin/sh\nprintf "Darwin\\n"\n' >"$test_root/bin/uname"
  chmod +x "$test_root/bin/op" "$test_root/bin/uname" "$HNET_SECURITY_BIN"
}

write_edge_config() {
  cat >"$TELEMETRY_EDGE_ENV" <<'ENV'
AGENT_TELEMETRY_UPSTREAM=https://studio.example.ts.net:4319
AGENT_TELEMETRY_HOST=mac-mini-1
AGENT_TELEMETRY_INGEST_TOKEN=op://TEST/agent-telemetry/mac-mini-1-token
ENV
  printf '%032d' 1 >"$HNET_TEST_TOKEN_FILE"
  printf '# Existing shell settings\n' >"$ZDOTDIR/.zshrc"
}

test_enable_is_repeatable_and_keeps_secrets_out_of_startup() {
  "$repo_dir/ops/apps/hnetctl/hnetctl" shell-enable
  "$repo_dir/ops/apps/hnetctl/hnetctl" shell-enable
  "$repo_dir/ops/apps/hnetctl/hnetctl" shell-status
  cmp -s "$HNET_TEST_STORE" "$HNET_TEST_TOKEN_FILE" || fail "Wrong token stored."
  [[ $(grep -Fc '# >>> hnet zsh >>>' "$ZDOTDIR/.zshrc") == 1 ]] || fail "Duplicate startup entry."
  [[ $(head -1 "$ZDOTDIR/.zshrc") == '# Existing shell settings' ]] || fail "Existing settings changed."
  if grep -Fqf "$HNET_TEST_TOKEN_FILE" "$ZDOTDIR/.zshrc" "$HNET_TEST_ARGS"; then
    fail "Token appeared in startup or process arguments."
  fi
}

test_failed_keychain_write_does_not_install_startup() {
  local alternate="$test_root/failed-startup"
  mkdir -p "$alternate"
  printf '%032d' 2 >"$HNET_TEST_TOKEN_FILE"
  if HNET_TEST_FAIL_STORE=1 ZDOTDIR="$alternate" \
    "$repo_dir/ops/apps/hnetctl/hnetctl" shell-enable >/dev/null 2>&1; then
    fail "Failed Keychain write was accepted."
  fi
  [[ ! -e $alternate/.zshrc ]] || fail "Startup installed after Keychain failure."
}

test_fresh_shell_loads_hooks_once() {
  zsh -fi -c '
    source "$1"
    source "$1"
    [[ $_AGENT_TELEMETRY_LOADED == 1 ]] || exit 1
    [[ ${#preexec_functions} == 1 && ${#precmd_functions} == 1 ]] || exit 1
    [[ $AGENT_TELEMETRY_INGEST_TOKEN == "$(cat "$HNET_TEST_STORE")" ]] || exit 1
  ' zsh "$repo_dir/ops/clients/zsh/auto.zsh"
}

test_missing_locked_and_invalid_tokens_leave_shell_usable() {
  HNET_TEST_LOCKED=1 zsh -fi -c '
    source "$1"
    [[ -z ${_AGENT_TELEMETRY_LOADED:-} ]]
  ' zsh "$repo_dir/ops/clients/zsh/auto.zsh"
  printf short >"$HNET_TEST_STORE"
  zsh -fi -c 'source "$1"; [[ -z ${_AGENT_TELEMETRY_LOADED:-} ]]' \
    zsh "$repo_dir/ops/clients/zsh/auto.zsh"
  rm "$HNET_TEST_STORE"
  zsh -fi -c 'source "$1"; [[ -z ${_AGENT_TELEMETRY_LOADED:-} ]]' \
    zsh "$repo_dir/ops/clients/zsh/auto.zsh"
}

test_autoload_does_not_trace_the_token() {
  printf '%032d' 1 >"$HNET_TEST_STORE"
  zsh -xfi -c 'source "$1"' zsh "$repo_dir/ops/clients/zsh/auto.zsh" \
    >"$test_root/trace" 2>&1
  if grep -Fqf "$HNET_TEST_STORE" "$test_root/trace"; then
    fail "Shell tracing exposed the token."
  fi
}

main
