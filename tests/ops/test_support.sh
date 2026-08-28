#!/usr/bin/env bash

set -euo pipefail

script_path=${BASH_SOURCE[0]}
script_parent=${script_path%/*}
script_dir=$(cd -- "$script_parent" && pwd)
repo_dir=$(cd -- "$script_dir/../.." && pwd)
tmp_dir="$repo_dir/tmp"
mkdir -p "$tmp_dir"
test_root=$(mktemp -d "$tmp_dir/hnet-tests.XXXXXX")

cleanup() {
  rm -rf "$test_root"
}

trap cleanup EXIT

fail() {
  echo "$1" >&2
  exit 1
}

assert_contains() {
  local haystack=$1 needle=$2
  [[ $haystack == *"$needle"* ]] || fail "Expected output to contain: $needle"
}

assert_file() {
  [[ -f $1 ]] || fail "Expected file: $1"
}

make_fake_tools() {
  local fake_bin="$test_root/bin"
  mkdir -p "$fake_bin"

  cat >"$fake_bin/shellcheck" <<'TOOL'
#!/bin/sh
printf '%s\n' "$@" >> "${OPS_TEST_SHELLCHECK_LOG:?}"
TOOL

  cat >"$fake_bin/zsh" <<'TOOL'
#!/bin/sh
printf '%s\n' "$@" >> "${OPS_TEST_ZSH_LOG:?}"
TOOL

  cat >"$fake_bin/shfmt" <<'TOOL'
#!/bin/sh
printf '%s\n' "$@" >> "${OPS_TEST_SHFMT_LOG:?}"
TOOL

  cat >"$fake_bin/docker" <<'TOOL'
#!/bin/sh
printf '%s\n' "$@" >> "${OPS_TEST_DOCKER_LOG:?}"
TOOL

  cat >"$fake_bin/helm" <<'TOOL'
#!/bin/sh
printf '%s\n' "$@" >> "${OPS_TEST_HELM_LOG:?}"
TOOL

  chmod +x "$fake_bin/shellcheck" "$fake_bin/zsh" "$fake_bin/shfmt" "$fake_bin/docker" "$fake_bin/helm"
}
