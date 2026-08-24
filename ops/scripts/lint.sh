#!/usr/bin/env bash

set -euo pipefail

script_path=${BASH_SOURCE[0]}
script_parent=${script_path%/*}
script_dir=$(cd -- "$script_parent" && pwd)
repo_dir=$(cd -- "$script_dir/../.." && pwd)

fail() {
  echo "$1" >&2
  exit "${2:-1}"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

cd "$repo_dir"
require_command shellcheck
require_command zsh

shellcheck \
  ops/apps/hnetctl/hnetctl \
  ops/telemetry/*.sh \
  ops/telemetry/clickhouse/*.sh \
  ops/scripts/*.sh \
  tests/*.sh
zsh -n ops/clients/zsh/*.zsh
