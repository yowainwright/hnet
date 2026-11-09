#!/usr/bin/env bash

set -euo pipefail

script_parent=${BASH_SOURCE[0]%/*}
repo_dir=$(cd -- "$script_parent/../.." && pwd)

main() {
  [[ $# -le 1 ]] || fail "Usage: release.sh [--preview|--publish]"
  local mode=${1:---preview}
  case "$mode" in
  --preview | --publish) ;;
  --help)
    echo "Usage: release.sh [--preview|--publish]"
    return
    ;;
  *) fail "Usage: release.sh [--preview|--publish]" ;;
  esac
  cd "$repo_dir"
  release_context
  release_run "$mode"
}

release_run() {
  local mode=${1:?}
  if [[ $mode == --publish ]]; then release_preflight; fi
  release_build
  release_notes
  if [[ $mode == --publish ]]; then
    release_publish
    return
  fi
  echo "Preview ready in the release directory; nothing published."
  echo "After review and merge, run: ./ops/scripts/release.sh --publish"
}

release_context() {
  version=$(<VERSION)
  [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "VERSION must be a stable semantic version."
  revision=$(git rev-parse HEAD)
  source_state=clean
  [[ -z $(git status --porcelain) ]] || source_state="uncommitted changes"
  repo=$(jq -er '.repo' ops/clients/homebrew-hnet.json)
  [[ $repo =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || fail "Invalid release repository."
  output=${HNET_RELEASE_DIR:-"$repo_dir/dist"}
  [[ $output == /* ]] || output="$repo_dir/$output"
  export HNET_RELEASE_DIR="$output"
  notes="$output/hnet-$version-NOTES.md"
}

release_preflight() {
  command -v gh >/dev/null 2>&1 || fail "GitHub CLI is required to publish."
  [[ -z $(git status --porcelain) ]] || fail "Publish requires a clean checkout; commit and merge changes first."
  local remote_main private tag_count
  remote_main=$(gh api --method GET "repos/$repo/git/ref/heads/main" --jq '.object.sha')
  [[ $remote_main == "$revision" ]] || fail "Publish requires the reviewed GitHub main revision."
  private=$(gh api --method GET "repos/$repo" --jq '.private')
  [[ $private == false ]] || fail "The public Homebrew release requires a public repository."
  tag_count=$(gh api --method GET "repos/$repo/git/matching-refs/tags/v$version" \
    --jq "map(select(.ref == \"refs/tags/v$version\")) | length")
  [[ $tag_count == 0 ]] || fail "Release tag already exists; never replace published assets."
  release_check_ci
}

release_check_ci() {
  local checks
  checks=$(gh api --method GET --paginate --slurp "repos/$repo/commits/$revision/check-runs?per_page=100")
  jq -e '
    [.[] | .check_runs[] | select(.app.id == 15368)] as $checks |
    ["validate", "macos-client"] | all(
      . as $name |
      [$checks[] | select(.name == $name)] | max_by(.id) |
      .status == "completed" and .conclusion == "success"
    )' <<<"$checks" >/dev/null || fail "Latest Linux and macOS GitHub Actions checks must pass."
}

release_build() {
  "$repo_dir/tests/ops/clients/release_test.sh"
  "$repo_dir/ops/scripts/secret-scan.sh"
  "$repo_dir/ops/apps/hnetctl/hnetctl" release-bundle
  (cd "$output" && shasum -a 256 -c "hnet-$version-SHA256SUMS")
}

release_notes() {
  cat >"$notes" <<EOF
# hnet $version preview

Package preview from commit $revision for trusted Macs using Codex and Claude Code.
Source tree: $source_state.
This is an unsupported prerelease for evaluating installation and enrollment.

Archives include portable scripts, configuration, and the MIT license. Applications
and container images are separate prerequisites. Enrollment is explicit.

Known limits: strict queued-record expiry, backup restore/retention verification,
local backup staging expiry, build provenance, and real Homebrew validation across
both Mac architectures remain supported-release gates. Durable queues are retained.
General ChatGPT conversation tracking is unverified; Kubernetes is experimental.
EOF
}

release_publish() {
  [[ -z $(git status --porcelain) ]] || fail "Checkout changed during preparation; publication stopped."
  [[ $(git rev-parse HEAD) == "$revision" ]] || fail "HEAD changed during preparation; publication stopped."
  gh release create "v$version" --repo "$repo" --target "$revision" \
    --title "hnet $version preview" --prerelease --latest=false --notes-file "$notes" \
    "$output/hnet-$version-darwin-arm64.tar.gz" \
    "$output/hnet-$version-darwin-amd64.tar.gz" \
    "$output/hnet-$version-SHA256SUMS"
}

fail() {
  echo "$1" >&2
  exit 1
}

main "$@"
