#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=tests/ops/test_support.sh
source "${BASH_SOURCE[0]%/*}/../../test_support.sh"

main() {
  configure_clients_fixture
  test_dynamic_registration_and_retry
  test_partial_apply_is_retryable
  test_registration_confirmation
  test_registration_guards
  test_inventory_guards
  test_configured_fleet_size
  echo "Dynamic client registration and retry tests passed."
}

configure_clients_fixture() {
  export HNET_CLIENTS_FILE="$test_root/clients.json"
  export TELEMETRY_STUDIO_ENV="$test_root/central.env"
  export HNET_TEST_REGISTRY="$test_root/items.json" HNET_TEST_CALLS="$test_root/calls"
  export HNET_TEST_RENDERED="$test_root/rendered.json"
  export HNET_PACKAGE_ROOT="$repo_dir" HNET_CLIENT_HOME="$test_root/state"
  export HNET_TEST_ENROLLMENTS="$HNET_CLIENT_HOME/ops/telemetry/enrollments"
  export PATH="$test_root/bin:$PATH"
  mkdir -p "$test_root/bin"
  mkdir -p "$HNET_CLIENT_HOME/ops/telemetry"
  printf '[]\n' >"$HNET_TEST_REGISTRY"
  jq '.[0].name = "hub" | .[0].tokenRef = "op://TEST/agent-telemetry/central-token"' \
    "$repo_dir/ops/telemetry/clients.example.json" >"$HNET_CLIENTS_FILE"
  cp "$repo_dir/ops/telemetry/.env.mac-studio.example" "$TELEMETRY_STUDIO_ENV"
  write_clients_fake_tools
}

write_clients_fake_tools() {
  local tool
  export HNET_TEST_TOOL_LOG="$HNET_TEST_CALLS"
  for tool in op docker tailscale curl; do
    cp "$repo_dir/tests/ops/clients/tool_fixture.sh" "$test_root/bin/$tool"
    chmod +x "$test_root/bin/$tool"
  done
}

test_dynamic_registration_and_retry() {
  printf 'yes\n' | "$repo_dir/ops/apps/hnetctl/hnetctl" client-add travel-laptop >"$test_root/registration.log" 2>&1
  jq -e 'length == 2 and .[1].name == "travel-laptop" and .[1].port == 4319 and .[1].hostPort == 14319' "$HNET_CLIENTS_FILE" >/dev/null
  add_fixture_client travel-laptop
  [[ $(jq length "$HNET_TEST_REGISTRY") == 1 ]] || fail "Repeated registration created another credential."
  jq -e '.services.collector.ports == ["127.0.0.1:14318:4318", "127.0.0.1:14319:4319"]' "$HNET_TEST_RENDERED" >/dev/null
  grep -Fq 'AGENT_TELEMETRY_HOST=travel-laptop' "$HNET_TEST_ENROLLMENTS/travel-laptop.env"
  grep -Fq 'https=4319' "$HNET_TEST_CALLS"
  local secret
  secret=$(printf '%064d' 5)
  if grep -Fq "$secret" "$HNET_CLIENTS_FILE" "$HNET_TEST_RENDERED" "$test_root/registration.log"; then
    fail "A resolved token escaped into public configuration or output."
  fi
}

test_partial_apply_is_retryable() {
  if HNET_TEST_APPLY_FAIL=1 add_fixture_client build-agent; then
    fail "Failed central startup reported success."
  fi
  jq -e 'length == 3 and .[2].name == "build-agent"' "$HNET_CLIENTS_FILE" >/dev/null
  add_fixture_client build-agent
  [[ $(jq length "$HNET_TEST_REGISTRY") == 2 ]] || fail "Retry rotated or duplicated an existing credential."
  [[ ! -d $HNET_CLIENTS_FILE.lock ]] || fail "Registration left its lock behind."
}

test_registration_confirmation() {
  local result=0
  printf 'n\n' | "$repo_dir/ops/apps/hnetctl/hnetctl" client-add declined >"$test_root/registration.log" 2>&1 || result=$?
  [[ $result -ne 0 ]] || fail "Declined registration proceeded."
}

test_registration_guards() {
  local before
  before=$(jq length "$HNET_CLIENTS_FILE")
  if HNET_TEST_OP_FAIL=1 add_fixture_client denied; then
    fail "A denied 1Password request reported success."
  fi
  [[ $(jq length "$HNET_CLIENTS_FILE") == "$before" ]] || fail "Failed credential setup changed the inventory."
  if add_fixture_client ../escape; then
    fail "Unsafe client name was accepted."
  fi
  if add_fixture_client TRAVEL-LAPTOP; then
    fail "Client names collided on a case-insensitive filesystem."
  fi
  mkdir "$HNET_CLIENTS_FILE.lock"
  if add_fixture_client blocked; then
    fail "Concurrent registration bypassed the inventory lock."
  fi
  rmdir "$HNET_CLIENTS_FILE.lock"
}

test_configured_fleet_size() {
  local fleet="$test_root/fleet.json"
  jq -n '[range(0; 50) | {name: ("worker-" + tostring), port: (5000 + .), hostPort: (15000 + .), tokenRef: ("op://TEST/client-" + tostring + "/password")}]' >"$fleet"
  HNET_CLIENTS_FILE="$fleet" "$repo_dir/ops/apps/hnetctl/hnetctl" status >"$test_root/fleet-status.log" 2>&1
  jq -e '.services.collector.ports | length == 50' "$HNET_TEST_RENDERED" >/dev/null ||
    fail "Configured fleet was truncated."
}

test_inventory_guards() {
  local bad="$test_root/invalid.json" before
  before=$(jq length "$HNET_TEST_REGISTRY")
  jq '.[1].port = .[0].port' "$HNET_CLIENTS_FILE" >"$bad"
  if HNET_CLIENTS_FILE="$bad" add_fixture_client invalid; then
    fail "Duplicate receiver ports were accepted."
  fi
  jq '.[0].tokenRef = "resolved-secret-is-forbidden"' "$HNET_CLIENTS_FILE" >"$bad"
  if HNET_CLIENTS_FILE="$bad" add_fixture_client invalid; then
    fail "An inventory with a literal credential was accepted."
  fi
  ln -s "$HNET_CLIENTS_FILE" "$test_root/inventory-link.json"
  if HNET_CLIENTS_FILE="$test_root/inventory-link.json" add_fixture_client invalid; then
    fail "A symlink inventory was accepted."
  fi
  [[ $(jq length "$HNET_TEST_REGISTRY") == "$before" ]] || fail "Invalid inventory created a credential."
}

add_fixture_client() {
  "$repo_dir/ops/apps/hnetctl/hnetctl" client-add "${1:?}" --yes >"$test_root/registration.log" 2>&1
}

main
