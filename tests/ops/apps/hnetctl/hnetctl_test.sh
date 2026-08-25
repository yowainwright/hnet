#!/usr/bin/env bash

set -euo pipefail

script_path=${BASH_SOURCE[0]}
script_parent=${script_path%/*}
script_dir=$(cd -- "$script_parent" && pwd)
# shellcheck source=tests/ops/test_support.sh
source "$script_dir/../../test_support.sh"

test_hnetctl_resolves_the_ops_telemetry_path() {
  local output exit_code=0
  output=$(
    cd "$repo_dir/ops/telemetry"
    env -u TELEMETRY_STUDIO_ENV -u TELEMETRY_EDGE_ENV \
      PATH="$test_root/bin:$PATH" \
      OPS_TEST_DOCKER_LOG="$test_root/hnetctl-docker.log" \
      "$repo_dir/ops/apps/hnetctl/hnetctl" status 2>&1
  ) || exit_code=$?

  [[ $exit_code -ne 0 ]] || fail "hnetctl status unexpectedly succeeded without configuration."
  assert_contains "$output" "$repo_dir/ops/telemetry/.env.mac-studio"
}

make_fake_tools
test_hnetctl_resolves_the_ops_telemetry_path

echo "hnetctl tests passed."
