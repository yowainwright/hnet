#!/usr/bin/env bash

set -euo pipefail

script_path=${BASH_SOURCE[0]}
script_dir=$(cd -- "${script_path%/*}" && pwd)
repo_dir=$(cd -- "$script_dir/../../.." && pwd)
# shellcheck source=tests/ops/test_support.sh
source "$script_dir/../test_support.sh"

make_runner_fakes() {
  local fake_bin="$test_root/runner-bin"
  mkdir -p "$fake_bin"
  cat >"$fake_bin/uname" <<'TOOL'
#!/bin/sh
case "${1:-}" in
  -s) printf '%s\n' Darwin ;;
  -m) printf '%s\n' arm64 ;;
esac
TOOL
  cat >"$fake_bin/gh" <<'TOOL'
#!/bin/sh
case "${1:-}" in
  auth) exit 0 ;;
  *) exit 0 ;;
esac
TOOL
  cat >"$fake_bin/launchctl" <<'TOOL'
#!/bin/sh
exit 0
TOOL
  chmod +x "$fake_bin/uname" "$fake_bin/gh" "$fake_bin/launchctl"
  printf '%s\n' "$fake_bin"
}

test_help() {
  local output
  output=$("$repo_dir/ops/runners/setup.sh" --help)
  assert_contains "$output" '--repo OWNER/REPO'
  assert_contains "$output" '--dry-run'
}

test_dry_run() {
  local fake_bin output runner_root
  fake_bin=$(make_runner_fakes)
  runner_root="$HOME/.hnet-test-runners-$$"
  output=$(PATH="$fake_bin:$PATH" HNET_RUNNER_ROOT="$runner_root" \
    "$repo_dir/ops/runners/setup.sh" --repo yowainwright/hnet --dry-run)
  assert_contains "$output" 'Would register yowainwright/hnet'
  assert_contains "$output" 'Would use labels: self-hosted,macos,ci,hnet-ci'
  [[ ! -e $runner_root ]] || fail 'Dry run created runner files.'
}

test_setup_rejects_unknown_repository() {
  local fake_bin invalid_repo
  fake_bin=$(make_runner_fakes)
  for invalid_repo in missing-slash /name owner/ owner/repo/extra 'bad repo/name'; do
    if PATH="$fake_bin:$PATH" "$repo_dir/ops/runners/setup.sh" \
      --repo "$invalid_repo" --dry-run >/dev/null 2>&1; then
      fail 'Invalid repository was accepted.'
    fi
  done
}

write_runner_package() {
  local package=$1
  mkdir -p "$package"
  cat >"$package/config.sh" <<'TOOL'
#!/bin/sh
if [ "${1:-}" = remove ]; then
  test-step remove
else
  test-step configure
fi
TOOL
  cat >"$package/svc.sh" <<'TOOL'
#!/bin/sh
test-step "$1"
TOOL
  chmod +x "$package/config.sh" "$package/svc.sh"
}

write_runner_api_fake() {
  cat >"$1/gh" <<'TOOL'
#!/bin/sh
case "$*" in
  *releases/latest*) test-step release || exit "$?"; printf v1.0.0 ;;
  *registration-token*) test-step registration || exit "$?"; printf synthetic-registration ;;
  *remove-token*) test-step removal-token || exit "$?"; printf synthetic-removal ;;
  *) exit 1 ;;
esac
TOOL
}

write_runner_download_fakes() {
  cat >"$1/curl" <<'TOOL'
#!/bin/sh
test-step download
TOOL
  cat >"$1/tar" <<'TOOL'
#!/bin/sh
test-step extract || exit "$?"
[ "$OPS_TEST_FAIL_STEP" != invalid-archive ] || exit 0
cp -R "$OPS_TEST_PACKAGE/." "$4/"
TOOL
}

make_transaction_fakes() {
  local fake_bin
  fake_bin=$(make_runner_fakes)
  cat >"$fake_bin/test-step" <<'TOOL'
#!/bin/sh
printf '%s\n' "$1" >> "$OPS_TEST_STEPS"
[ "$1" != "$OPS_TEST_FAIL_STEP" ] || exit 73
TOOL
  write_runner_api_fake "$fake_bin"
  write_runner_download_fakes "$fake_bin"
  chmod +x "$fake_bin"/*
  printf '%s\n' "$fake_bin"
}

run_runner_transaction() {
  local fixture=$1 fail_step=$2 source_code script
  source_code=$(sed '/^while ((\$# > 0)); do/,$d' "$repo_dir/ops/runners/setup.sh")
  # shellcheck disable=SC2016 # Variables expand in the child Bash process.
  script=$source_code'
repo_dir="$OPS_TEST_FIXTURE/project"
runner_root="$OPS_TEST_FIXTURE/runners"
repo=example/project
runner_name=synthetic-runner
replace=true
trap cleanup EXIT
setup_runner'
  env PATH="$transaction_bin:$PATH" OPS_TEST_FIXTURE="$fixture" \
    OPS_TEST_PACKAGE="$test_root/package" OPS_TEST_STEPS="$fixture/steps" \
    OPS_TEST_FAIL_STEP="$fail_step" \
    bash -c "$script" "$repo_dir/ops/runners/setup.sh"
}

make_existing_runner() {
  local runner_dir="$1/runners/example-project"
  write_runner_package "$runner_dir"
  mkdir -p "$runner_dir/_work"
  touch "$runner_dir/.runner" "$runner_dir/_work/preserved"
}

test_failed_preparation_preserves_runner() {
  local step fixture result
  for step in release download extract invalid-archive registration removal-token; do
    fixture="$test_root/failure-$step"
    make_existing_runner "$fixture"
    result=0
    run_runner_transaction "$fixture" "$step" >/dev/null 2>&1 || result=$?
    [[ $result -ne 0 ]] || fail "Failed runner preparation reported success."
    assert_file "$fixture/runners/example-project/.runner"
    assert_file "$fixture/runners/example-project/_work/preserved"
    if grep -Eq '^(stop|uninstall|remove|configure|install|start)$' "$fixture/steps"; then
      fail "Runner was changed before preparation succeeded."
    fi
  done
}

test_prepared_runner_replaces_existing_runner() {
  local fixture="$test_root/replacement" expected
  make_existing_runner "$fixture"
  run_runner_transaction "$fixture" none >/dev/null
  expected=$'release\ndownload\nextract\nregistration\nremoval-token\nstop\nuninstall\nremove\nconfigure\ninstall\nstart'
  [[ $(<"$fixture/steps") == "$expected" ]] || fail "Runner replacement order is incorrect."
  assert_file "$fixture/runners/example-project/.hnet-repo"
}

test_help
test_dry_run
test_setup_rejects_unknown_repository
write_runner_package "$test_root/package"
transaction_bin=$(make_transaction_fakes)
test_failed_preparation_preserves_runner
test_prepared_runner_replaces_existing_runner
echo "runner setup tests passed."
