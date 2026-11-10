#!/usr/bin/env bash

set -euo pipefail

release_bundle() (
  [[ $# == 0 ]] || fail "Usage: hnetctl release-bundle"
  [[ -z ${HNET_PACKAGE_ROOT:-} ]] || fail "Build release previews from a reviewed source checkout."
  client_initialize bundle
  local version output stage arch
  version=${HNET_RELEASE_VERSION:-$(<"${client_source:?}/VERSION")}
  [[ $version =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$ ]] || fail "Invalid release version."
  output=${HNET_RELEASE_DIR:-"$client_source/dist"}
  mkdir -p "$output"
  stage=$(mktemp -d "$output/.hnet-release.XXXXXX")
  trap 'rm -rf -- "$stage"' EXIT
  release_stage "$stage/hnet" "$version"
  for arch in arm64 amd64; do
    client_archive "$stage" "$output/hnet-$version-darwin-$arch.tar.gz" hnet
  done
  (cd "$output" && shasum -a 256 "hnet-$version-darwin-arm64.tar.gz" "hnet-$version-darwin-amd64.tar.gz" >"hnet-$version-SHA256SUMS")
  echo "Created versioned macOS release previews; nothing published."
)

release_stage() {
  local destination=${1:?} version=${2:?} relative mode target
  while IFS= read -r relative; do
    release_validate_file "$relative"
    mode=644
    case "$relative" in *.sh | */hnetctl) mode=755 ;; esac
    target="$destination/$relative"
    install -d -m 755 "${target%/*}"
    install -m "$mode" "$client_source/$relative" "$target"
  done <"$client_source/ops/clients/release-files.txt"
  install -m 755 "$client_source/ops/clients/launcher.sh" "$destination/hnetctl"
  printf '%s\n' "$version" >"$destination/VERSION"
  (cd "$destination" && while IFS= read -r relative; do shasum -a 256 "$relative"; done <ops/clients/release-files.txt >SHA256SUMS)
}

release_validate_file() {
  local relative=${1:?}
  [[ $relative != /* && $relative != *..* && $relative != *' '* ]] || fail "Unsafe release manifest path."
  case "$relative" in
  LICENSE | VERSION | README.md | install.sh | ops/apps/hnetctl/* | ops/clients/* | ops/telemetry/*) ;;
  *) fail "Release file is outside the supported surface." ;;
  esac
  case "$relative" in
  */.env.*.example) ;;
  */.env* | */backups/* | */data/* | */queues/*) fail "Private state cannot be released." ;;
  esac
  client_reject_symlinks "$client_source/$relative"
  [[ -f "$client_source/$relative" ]] || fail "Required release file is missing."
}
