#!/usr/bin/env bash

set -euo pipefail

# shellcheck source=tests/ops/test_support.sh
source "${BASH_SOURCE[0]%/*}/../test_support.sh"

main() {
  export HNET_RELEASE_DIR="$test_root/release"
  "$repo_dir/ops/apps/hnetctl/hnetctl" release-bundle
  local version archive
  version=$(<"$repo_dir/VERSION")
  jq -e --arg version "$version" '.version == $version and .command == "hnetctl" and .managed == false' \
    "$repo_dir/ops/clients/homebrew-hnet.json" >/dev/null || fail "Tap draft and package version differ."
  archive="$HNET_RELEASE_DIR/hnet-$version-darwin-arm64.tar.gz"
  tar -xzf "$archive" -C "$test_root"
  (cd "$test_root/hnet" && shasum -a 256 -c SHA256SUMS >/dev/null)
  [[ -f "$test_root/hnet/LICENSE" && -f "$test_root/hnet/ops/telemetry/compose.mac-studio.yml" ]] || fail "Release resources missing."
  [[ $("$test_root/hnet/hnetctl" --version) == "hnetctl $version" ]] || fail "Archive launcher version failed."
  test_prefix "$test_root/apple" "$version"
  test_prefix "$test_root/intel" "$version"
  test_release_candidate
  echo "Versioned package, stable entrypoint, upgrade and removal tests passed."
}

test_release_candidate() {
  local candidate=0.2.0-rc.1 original
  original=$(<"$repo_dir/VERSION")
  HNET_RELEASE_VERSION="$candidate" "$repo_dir/ops/apps/hnetctl/hnetctl" release-bundle
  HNET_RELEASE_VERSION="$candidate" "$repo_dir/ops/scripts/verify-release-assets.sh" "$HNET_RELEASE_DIR" >/dev/null
  mkdir -p "$test_root/candidate"
  tar -xzf "$HNET_RELEASE_DIR/hnet-$candidate-darwin-arm64.tar.gz" -C "$test_root/candidate"
  (cd "$test_root/candidate/hnet" && shasum -a 256 -c SHA256SUMS >/dev/null)
  [[ $("$test_root/candidate/hnet/hnetctl" --version) == "hnetctl $candidate" ]] || fail "Candidate version missing."
  [[ $(<"$repo_dir/VERSION") == "$original" ]] || fail "Release changed source VERSION."
  printf '\ncorrupted\n' >>"$HNET_RELEASE_DIR/hnet-$candidate-darwin-arm64.tar.gz"
  if HNET_RELEASE_VERSION="$candidate" "$repo_dir/ops/scripts/verify-release-assets.sh" "$HNET_RELEASE_DIR" >/dev/null 2>&1; then
    fail "Release verifier accepted a modified archive."
  fi
}

test_prefix() {
  local root=${1:?} version=${2:?} prefix
  prefix="$root/Cellar/hnet/$version"
  install_package "$prefix"
  mkdir -p "$root/opt" "$root/bin"
  ln -s "../Cellar/hnet/$version" "$root/opt/hnet"
  ln -s ../opt/hnet/bin/hnetctl "$root/bin/hnetctl"
  [[ $("$root/bin/hnetctl" --version) == "hnetctl $version" ]] || fail "Installed symlink could not locate resources."
  if "$root/bin/hnetctl" up >/dev/null 2>&1; then
    fail "Package accepted an unsupported experimental command."
  fi
  test_upgrade "$root" "$version"
}

test_upgrade() {
  local root=${1:?} version=${2:?} before after
  install_package "$root/Cellar/hnet/0.1.1"
  printf '0.1.1\n' >"$root/Cellar/hnet/0.1.1/share/hnet/VERSION"
  mkdir -p "$root/state/ops/telemetry"
  printf 'private-placeholder\n' >"$root/state/ops/telemetry/.env.edge"
  before=$(shasum "$root/state/ops/telemetry/.env.edge")
  rm "$root/opt/hnet"
  ln -s ../Cellar/hnet/0.1.1 "$root/opt/hnet"
  [[ $(HNET_CLIENT_HOME="$root/state" "$root/bin/hnetctl" --version) == 'hnetctl 0.1.1' ]] || fail "Stable entrypoint used old code after upgrade."
  rm "$root/opt/hnet"
  after=$(shasum "$root/state/ops/telemetry/.env.edge")
  [[ $before == "$after" && -f "$root/Cellar/hnet/$version/share/hnet/VERSION" ]] || fail "Upgrade/removal changed private state or rollback code."
}

install_package() {
  local prefix=${1:?}
  mkdir -p "$prefix/bin" "$prefix/share/hnet"
  cp "$test_root/hnet/hnetctl" "$prefix/bin/hnetctl"
  cp -R "$test_root/hnet/ops" "$prefix/share/hnet/ops"
  cp "$test_root/hnet/VERSION" "$test_root/hnet/LICENSE" "$test_root/hnet/SHA256SUMS" "$test_root/hnet/install.sh" "$prefix/share/hnet/"
}

main
