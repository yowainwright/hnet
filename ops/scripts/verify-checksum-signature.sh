#!/usr/bin/env bash
set -euo pipefail

script_parent=${BASH_SOURCE[0]%/*}
repo_dir=$(cd -- "$script_parent/../.." && pwd)
asset_dir=${1:-dist}
version=${HNET_RELEASE_VERSION:-$(<"$repo_dir/VERSION")}
checksum="$asset_dir/hnet-$version-SHA256SUMS"
identity="https://github.com/yowainwright/hnet/.github/workflows/release.yml@refs/tags/v$version"

main() {
  test -s "$checksum"
  test -s "$checksum.bundle"
  cosign verify-blob --bundle "$checksum.bundle" \
    --certificate-identity "$identity" \
    --certificate-oidc-issuer https://token.actions.githubusercontent.com \
    "$checksum"
}

main
