#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=tests/ops/test_support.sh
source "${BASH_SOURCE[0]%/*}/../test_support.sh"

main() {
  configure_fixture
  test_bundle_is_portable_and_excludes_private_state
  test_relative_bundle_directory
  test_missing_prerequisites_stop_before_installation
  test_remote_docker_is_refused
  test_upstream_rejection_stops_before_installation
  test_symlink_destination_is_refused
  test_clean_install_and_repeat
  test_installed_shell_has_hnetctl
  test_doctor_is_read_only_and_checks_connections
  test_archive_checks_installed_enrollment
  test_package_enrollment_uses_stable_resources
  test_explicit_dependency_install
  test_conflicting_codex_telemetry_is_preserved
  test_bad_slot_configuration_is_rejected
  test_checksum_failure_stops_installation
  echo "Client installer, checker, and portable bundle tests passed."
}

configure_fixture() {
  export PATH="$test_root/bin:$PATH" ZDOTDIR="$test_root/shell"
  export HNET_TEST_TOOL_LOG="$test_root/tools.log" HNET_TEST_ARGS="$test_root/security.log"
  export HNET_TEST_STORE="$test_root/keychain-token" HNET_TEST_TOKEN_FILE="$test_root/source-token"
  export HNET_TEST_DEPS_INSTALLED="$test_root/deps-installed" HNET_CLIENT_APPLICATIONS_DIR="$test_root/apps"
  export HNET_SECURITY_BIN="$test_root/bin/security" HNET_SHELL_KEYCHAIN="$test_root/login.keychain-db"
  export HNET_CODEX_CONFIG="$test_root/codex.toml" HNET_CLIENT_BUNDLE_DIR="$test_root/distribution"
  mkdir -p "$test_root/bin" "$ZDOTDIR" "$HNET_CLIENT_APPLICATIONS_DIR/1Password.app"
  printf '%032d' 7 >"$HNET_TEST_TOKEN_FILE"
  touch "$HNET_SHELL_KEYCHAIN" "$HNET_TEST_TOOL_LOG"
  printf '# Existing startup\n' >"$ZDOTDIR/.zshrc"
  printf 'model = "fixture-model"\n' >"$HNET_CODEX_CONFIG"
  write_fake_tools
  write_enrollment_config
}

write_fake_tools() {
  local name
  for name in uname docker tailscale plutil codex op brew open pgrep; do
    cp "$repo_dir/tests/ops/clients/tool_fixture.sh" "$test_root/bin/$name"
    chmod +x "$test_root/bin/$name"
  done
  cp "$repo_dir/tests/ops/clients/zsh/security_fixture.sh" "$HNET_SECURITY_BIN"
  chmod +x "$HNET_SECURITY_BIN"
  cat >"$test_root/bin/curl" <<'TOOL'
#!/bin/sh
printf 'curl %s\n' "$*" >>"$HNET_TEST_TOOL_LOG"
cat >/dev/null
printf '%s' "${HNET_TEST_HTTP_STATUS:-200}"
TOOL
  chmod +x "$test_root/bin/curl"
}

write_enrollment_config() {
  cat >"$test_root/enrollment.env" <<'ENV'
AGENT_TELEMETRY_UPSTREAM=https://studio.example.ts.net:4319
AGENT_TELEMETRY_HOST=mac-mini-1
AGENT_TELEMETRY_INGEST_TOKEN=op://TEST/agent-telemetry/mac-mini-1-token
AGENT_TELEMETRY_REDACT_PATTERN=a^
ENV
}

test_bundle_is_portable_and_excludes_private_state() {
  "$repo_dir/ops/apps/hnetctl/hnetctl" client-bundle
  local archive="$HNET_CLIENT_BUNDLE_DIR/hnet-client-macos.tar.gz" listing
  listing=$(tar -tzf "$archive")
  [[ $listing == *hnet-client/install.sh* && $listing == *hnet-client/SHA256SUMS* ]] || fail "Bundle entrypoint or checksums missing."
  [[ $listing == *ops/clients/codex/config.toml* ]] || fail "Unpublished Codex client was omitted."
  if printf '%s\n' "$listing" | grep -Eq '/(\.git|backups|queues|data)/|/\.env\.edge$|/\.env\.mac-studio|compose\.mac-studio|grafana/'; then
    fail "Bundle contains private or central state."
  fi
  mkdir -p "$test_root/unpacked"
  tar -xzf "$archive" -C "$test_root/unpacked"
  client_package="$test_root/unpacked/hnet-client"
  (cd "$client_package" && shasum -a 256 -c SHA256SUMS >/dev/null)
  [[ ! -e "$client_package/.git" ]] || fail "Portable install depends on Git metadata."
}

test_relative_bundle_directory() {
  local process watchdog result=0
  (cd "$test_root" && exec bash -c 'source "$1"; client_reject_symlinks relative-dist' hnet-test "$repo_dir/ops/apps/hnetctl/client.sh") &
  process=$!
  (
    sleep 5
    kill "$process" 2>/dev/null || true
  ) &
  watchdog=$!
  wait "$process" || result=$?
  kill "$watchdog" 2>/dev/null || true
  wait "$watchdog" 2>/dev/null || true
  [[ $result == 0 ]] || fail "Relative bundle output failed or hung."
  (cd "$test_root" && HNET_CLIENT_BUNDLE_DIR=relative-dist "$repo_dir/ops/apps/hnetctl/hnetctl" client-bundle)
  [[ -f "$test_root/relative-dist/hnet-client-macos.tar.gz" ]] || fail "Relative bundle output is missing."
}

test_missing_prerequisites_stop_before_installation() {
  local prefix="$test_root/missing-install" output
  if output=$(HNET_TEST_MISSING=codex "$client_package/install.sh" --yes \
    --prefix "$prefix" --config "$test_root/enrollment.env" 2>&1); then
    fail "Missing prerequisite was ignored."
  fi
  [[ $output == *'Codex CLI'* ]] || fail "Missing prerequisite has no actionable message."
  [[ ! -e $prefix ]] || fail "Installer changed the destination before prerequisites passed."
  [[ ! -e $HNET_TEST_DEPS_INSTALLED ]] || fail "Dependency installation was not explicitly requested."
}

test_remote_docker_is_refused() {
  local output
  if output=$(HNET_TEST_DOCKER_ENDPOINT=ssh://fixture "$client_package/install.sh" --check --prerequisites 2>&1); then
    fail "Remote Docker context was accepted."
  fi
  [[ $output == *'remote engines are refused'* ]] || fail "Remote Docker failure was unclear."
}

test_upstream_rejection_stops_before_installation() {
  local output prefix="$test_root/rejected-upstream"
  if output=$(HNET_TEST_HTTP_STATUS=401 "$client_package/install.sh" --yes \
    --prefix "$prefix" --config "$test_root/enrollment.env" 2>&1); then
    fail "Installer ignored an upstream credential rejection."
  fi
  [[ $output == *'HTTP 401'* ]] || fail "Credential rejection was not explained."
  [[ ! -e $prefix ]] || fail "Unverified credentials changed the destination."
}

test_symlink_destination_is_refused() {
  local prefix="$test_root/symlink-install" output
  mkdir -p "$prefix/ops/telemetry"
  printf 'hnet-client-v1\n' >"$prefix/.hnet-client"
  ln -s "$test_root/outside.env" "$prefix/ops/telemetry/.env.edge"
  if output=$("$client_package/install.sh" --yes --prefix "$prefix" \
    --config "$test_root/enrollment.env" 2>&1); then
    fail "Installer followed a destination symlink."
  fi
  [[ $output == *'cannot traverse symlinks'* ]] || fail "Symlink refusal was unclear."
  [[ ! -e "$test_root/outside.env" ]] || fail "Installer wrote outside its destination."
}

test_clean_install_and_repeat() {
  client_prefix="$test_root/installed"
  "$client_package/install.sh" --yes --prefix "$client_prefix" --config "$test_root/enrollment.env"
  "$client_package/install.sh" --yes --prefix "$client_prefix" --config "$test_root/enrollment.env"
  [[ $(grep -Fc '# >>> hnet zsh >>>' "$ZDOTDIR/.zshrc") == 1 ]] || fail "Duplicate startup enrollment."
  [[ $(grep -Fc '# >>> hnet codex >>>' "$HNET_CODEX_CONFIG") == 1 ]] || fail "Duplicate Codex enrollment."
  [[ $(head -1 "$HNET_CODEX_CONFIG") == 'model = "fixture-model"' ]] || fail "Existing Codex settings changed."
  cmp -s "$test_root/enrollment.env" "$client_prefix/ops/telemetry/.env.edge" || fail "Enrollment references changed."
  [[ $(<"$HNET_TEST_STORE") == "$(<"$HNET_TEST_TOKEN_FILE")" ]] || fail "Keychain did not receive the token."
  assert_no_secret_leaks
}

test_doctor_is_read_only_and_checks_connections() {
  local before after
  before=$(grep -Ec 'compose .* (pull|up)|^op read |^-i$' "$HNET_TEST_TOOL_LOG" "$HNET_TEST_ARGS")
  "$client_prefix/ops/apps/hnetctl/hnetctl" client-check
  after=$(grep -Ec 'compose .* (pull|up)|^op read |^-i$' "$HNET_TEST_TOOL_LOG" "$HNET_TEST_ARGS")
  [[ $before == "$after" ]] || fail "Ordinary checks changed live state or read the ingestion secret."
  "$client_prefix/ops/apps/hnetctl/hnetctl" client-check --connection
  assert_no_secret_leaks
}

test_installed_shell_has_hnetctl() {
  zsh -fi -c 'source "$ZDOTDIR/.zshrc"; hnetctl client-check --prerequisites'
}

test_archive_checks_installed_enrollment() {
  HNET_CLIENT_HOME="$client_prefix" "$client_package/install.sh" --check
  HNET_CLIENT_HOME="$client_prefix" "$client_package/install.sh" --check --connection
  [[ ! -e "$client_package/ops/telemetry/.env.edge" ]] || fail "Archive checker created private configuration."
  assert_no_secret_leaks
}

test_package_enrollment_uses_stable_resources() {
  local root="$test_root/brew" prefix entry
  HNET_RELEASE_DIR="$root/dist" "$repo_dir/ops/apps/hnetctl/hnetctl" release-bundle
  mkdir -p "$root/unpacked"
  tar -xzf "$root/dist/hnet-$(<"$repo_dir/VERSION")-darwin-arm64.tar.gz" -C "$root/unpacked"
  prefix="$root/Cellar/hnet/$(<"$repo_dir/VERSION")"
  mkdir -p "$prefix/bin" "$prefix/share" "$root/opt"
  cp -R "$root/unpacked/hnet" "$prefix/share/hnet"
  mv "$prefix/share/hnet/hnetctl" "$prefix/bin/hnetctl"
  ln -s "../Cellar/hnet/$(<"$repo_dir/VERSION")" "$root/opt/hnet"
  entry="$root/opt/hnet/bin/hnetctl"
  "$entry" client-install --yes --prefix "$client_prefix" --config "$test_root/enrollment.env"
  HNET_CLIENT_HOME="$client_prefix" "$entry" client-check
  env -u HNET_CLIENT_BUNDLE_DIR HNET_CLIENT_HOME="$client_prefix" "$entry" client-bundle
  [[ -f "$client_prefix/dist/hnet-client-macos.tar.gz" ]] || fail "Packaged bundle wrote outside persistent state."
  zsh -fi -c 'source "$ZDOTDIR/.zshrc"; hnetctl --version'
  rm "$root/opt/hnet"
  zsh -fi -c 'source "$ZDOTDIR/.zshrc"'
  assert_no_secret_leaks
}

test_explicit_dependency_install() {
  HNET_TEST_MISSING=codex "$client_package/install.sh" --yes --install-deps \
    --prefix "$client_prefix" --config "$test_root/enrollment.env"
  [[ -f $HNET_TEST_DEPS_INSTALLED ]] || fail "Requested dependency install did not run."
  grep -Fq 'brew bundle install --no-upgrade --file' "$HNET_TEST_TOOL_LOG" || fail "Installer did not use the client Brewfile."
}

test_conflicting_codex_telemetry_is_preserved() {
  local alternate="$test_root/conflicting-codex.toml"
  printf '[otel]\nexporter = "none"\n' >"$alternate"
  if HNET_CODEX_CONFIG="$alternate" "$client_package/install.sh" --yes \
    --prefix "$client_prefix" --config "$test_root/enrollment.env" >/dev/null 2>&1; then
    fail "Installer overwrote existing telemetry."
  fi
  [[ $(wc -l <"$alternate") -eq 2 ]] || fail "Existing telemetry configuration changed."
}

test_bad_slot_configuration_is_rejected() {
  sed 's/:4319/:4320/' "$test_root/enrollment.env" >"$test_root/wrong-slot.env"
  if "$client_package/install.sh" --yes --prefix "$test_root/wrong-slot" \
    --config "$test_root/wrong-slot.env" >/dev/null 2>&1; then
    fail "Mismatched port and identity were accepted."
  fi
  [[ ! -e "$test_root/wrong-slot" ]] || fail "Invalid configuration created an installation."
}

test_checksum_failure_stops_installation() {
  printf '\n' >>"$client_package/ops/clients/codex/config.toml"
  if "$client_package/install.sh" --yes --prefix "$test_root/tampered" \
    --config "$test_root/enrollment.env" >/dev/null 2>&1; then
    fail "Tampered bundle was installed."
  fi
  [[ ! -e "$test_root/tampered" ]] || fail "Tampered source changed the destination."
}
assert_no_secret_leaks() {
  grep -Fqf "$HNET_TEST_TOKEN_FILE" "$ZDOTDIR/.zshrc" "$HNET_CODEX_CONFIG" \
    "$HNET_TEST_TOOL_LOG" "$HNET_TEST_ARGS" "$client_prefix/ops/telemetry/.env.edge" || return 0
  fail "Resolved token escaped into configuration, startup, or command arguments."
}

main
