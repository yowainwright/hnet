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

assert_contains() {
  local haystack=$1 needle=$2
  [[ $haystack == *"$needle"* ]] || fail "Expected output to contain: $needle"
}

assert_file() {
  [[ -f $1 ]] || fail "Expected file: $1"
}

fail() {
  echo "$1" >&2
  exit 1
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
if [ "${1:-}" = info ]; then
  exit "${OPS_TEST_DOCKER_INFO_EXIT_CODE:-0}"
fi
TOOL

  cat >"$fake_bin/helm" <<'TOOL'
#!/bin/sh
printf '%s\n' "$@" >> "${OPS_TEST_HELM_LOG:?}"
TOOL

  cat >"$fake_bin/kubectl" <<'TOOL'
#!/bin/sh
printf '%s\n' "$@" >> "${OPS_TEST_KUBECTL_LOG:?}"
while [ "$#" -gt 0 ]; do
  case "$1" in
  --kubeconfig | --context | --namespace)
    shift 2
    ;;
  *)
    break
    ;;
  esac
done
case "${1:-}" in
create)
  printf 'apiVersion: v1\nkind: List\nitems: []\n'
  ;;
apply)
  cat >/dev/null
  ;;
get)
  exit "${OPS_TEST_KUBECTL_EXIT_CODE:-0}"
  ;;
config)
  ;;
*)
  ;;
esac
TOOL

  cat >"$fake_bin/orbctl" <<'TOOL'
#!/bin/sh
printf '%s\n' "$@" >> "${OPS_TEST_ORBCTL_LOG:?}"
TOOL

  cat >"$fake_bin/k9s" <<'TOOL'
#!/bin/sh
printf '%s\n' "$@" >> "${OPS_TEST_K9S_LOG:?}"
TOOL

  cat >"$fake_bin/mprocs" <<'TOOL'
#!/bin/sh
printf '%s\n' "$@" >> "${OPS_TEST_MPROCS_LOG:?}"
TOOL

  cat >"$fake_bin/curl" <<'TOOL'
#!/bin/sh
printf '%s\n' "$@" >> "${OPS_TEST_CURL_LOG:?}"
TOOL

  cat >"$fake_bin/tailscale" <<'TOOL'
#!/bin/sh
printf '%s\n' "$@" >> "${OPS_TEST_TAILSCALE_LOG:?}"
TOOL

  chmod +x "$fake_bin/shellcheck" "$fake_bin/zsh" "$fake_bin/shfmt" \
    "$fake_bin/docker" "$fake_bin/helm" "$fake_bin/kubectl" \
    "$fake_bin/orbctl" "$fake_bin/k9s" "$fake_bin/mprocs" \
    "$fake_bin/curl" "$fake_bin/tailscale"
}

trap cleanup EXIT
