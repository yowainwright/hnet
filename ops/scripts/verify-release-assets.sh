#!/usr/bin/env bash
set -euo pipefail

script_parent=${BASH_SOURCE[0]%/*}
repo_dir=$(cd -- "$script_parent/../.." && pwd)
asset_dir=${1:-dist}
version=${2:-${HNET_RELEASE_VERSION:-$(<"$repo_dir/VERSION")}}

main() {
  [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || exit 1
  local checksum="$asset_dir/hnet-$version-SHA256SUMS" arch
  [[ -s $checksum && $(wc -l <"$checksum") -eq 2 ]] || exit 1
  for arch in arm64 amd64; do verify_asset "$arch" "$checksum"; done
  (cd "$asset_dir" && shasum -a 256 -c "hnet-$version-SHA256SUMS")
}

verify_asset() {
  local arch=${1:?} checksum=${2:?} name embedded_version
  name="hnet-$version-darwin-$arch.tar.gz"
  [[ -s $asset_dir/$name ]] || exit 1
  awk -v name="$name" '$2 == name && length($1) == 64 { found++ } END { exit found != 1 }' "$checksum"
  embedded_version=$(tar -xOf "$asset_dir/$name" hnet/VERSION) || exit 1
  [[ $embedded_version == "$version" ]] || exit 1
}

main
