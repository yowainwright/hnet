#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=tests/ops/test_support.sh
source "${BASH_SOURCE[0]%/*}/../../test_support.sh"

main() {
  [[ $(uname -s) == Darwin ]] || return 0
  configure_fixture
  write_probe_app
  write_open_adapter
  "$repo_dir/ops/apps/hnetctl/hnetctl" chatgpt-app
  wait_for_probe
  [[ $(<"$test_root/result") == passed ]] || fail "Desktop app lost its telemetry environment."
  echo "Native desktop environment handoff passed."
}

wait_for_probe() {
  local attempt
  for ((attempt = 0; attempt < 30; attempt++)); do
    [[ ! -f $test_root/result ]] || return 0
    sleep 0.1
  done
  fail "Desktop environment probe did not finish."
}

configure_fixture() {
  export HNET_TEST_APP="$test_root/Probe.app" HNET_TEST_STORE="$test_root/token"
  export HNET_TEST_ARGS="$test_root/security-args" HNET_SHELL_KEYCHAIN="$test_root/login.keychain-db"
  export HNET_SECURITY_BIN="$test_root/bin/security" HNET_CODEX_CONFIG="$test_root/codex.toml"
  export PATH="$test_root/bin:$PATH"
  mkdir -p "$test_root/bin" "$HNET_TEST_APP/Contents/MacOS"
  printf '%032d' 1 >"$HNET_TEST_STORE"
  touch "$HNET_SHELL_KEYCHAIN"
  cp "$repo_dir/tests/ops/clients/zsh/security_fixture.sh" "$HNET_SECURITY_BIN"
  printf '#!/bin/sh\nexit 1\n' >"$test_root/bin/pgrep"
  chmod +x "$HNET_SECURITY_BIN"
  chmod +x "$test_root/bin/pgrep"
  printf '# >>> hnet codex >>>\n' >"$HNET_CODEX_CONFIG"
  cat "$repo_dir/ops/clients/codex/config.toml" >>"$HNET_CODEX_CONFIG"
  printf '# <<< hnet codex <<<\n' >>"$HNET_CODEX_CONFIG"
}

write_probe_app() {
  cat >"$HNET_TEST_APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>dev.hnet.environment-probe</string>
<key>CFBundleExecutable</key><string>probe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSBackgroundOnly</key><true/>
</dict></plist>
PLIST
  write_probe_executable
}

write_probe_executable() {
  cat >"$HNET_TEST_APP/Contents/MacOS/probe" <<'PROBE'
#!/bin/sh
result="${0%/*}/../../../result"
expected='Authorization=Bearer 00000000000000000000000000000001'
if [ "${OTEL_EXPORTER_OTLP_HEADERS:-}" = "$expected" ] &&
  [ "${OTEL_EXPORTER_OTLP_LOGS_HEADERS:-}" = "$expected" ] &&
  [ "${OTEL_EXPORTER_OTLP_METRICS_HEADERS:-}" = "$expected" ] &&
  [ "${OTEL_EXPORTER_OTLP_LOGS_ENDPOINT:-}" = http://127.0.0.1:4318/v1/logs ]; then
  printf passed >"$result"
  exit 0
fi
printf failed >"$result"
PROBE
  chmod +x "$HNET_TEST_APP/Contents/MacOS/probe"
}

write_open_adapter() {
  cat >"$test_root/bin/open" <<'ADAPTER'
#!/bin/sh
[ "$1" = -a ] || exit 2
shift 2
exec /usr/bin/open -g -a "$HNET_TEST_APP" "$@"
ADAPTER
  chmod +x "$test_root/bin/open"
}

main
