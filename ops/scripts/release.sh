#!/usr/bin/env bash
set -euo pipefail

script_parent=${BASH_SOURCE[0]%/*}
repo_dir=$(cd -- "$script_parent/../.." && pwd)

release_entry() {
  [[ ${_HNET_RELEASE_SOURCED:-false} != true ]] || return 0
  release_main "$@"
}

release_main() {
  release_parse "$@" || return
  if [[ $mode == help ]]; then
    echo 'Usage: release.sh [--preview|--dry-run|--publish] [--patch|--minor|--major|vX.Y.Z[-rc.N]]'
    return
  fi
  release_prepare || return
  [[ $mode != preview && $mode != dry-run ]] || {
    echo "Preview passed; no GitHub state changed."
    return
  }
  release_confirm || return
  release_dispatch
}

release_prepare() {
  cd "$repo_dir" || return
  repo=$(jq -er '.repo' ops/clients/homebrew-hnet.json) || return
  revision=$(git rev-parse HEAD) || return
  source_state=clean
  [[ -z $(git status --porcelain) ]] || source_state='uncommitted changes'
  if [[ $mode != preview ]]; then release_preflight || return; fi
  release_select || return
  release_context || return
  if [[ $mode != preview ]]; then
    release_require_ready || return
    release_require_available || return
  fi
  release_build
}

release_parse() {
  mode=publish
  tag=''
  bump=''
  while [[ $# -gt 0 ]]; do
    release_parse_option "$1" || return
    shift
  done
  [[ -z $tag ]] || release_validate_tag "$tag"
}

release_parse_option() {
  case "${1:?}" in
  --preview) mode=preview ;;
  --dry-run) mode=dry-run ;;
  --publish) mode=publish ;;
  --help) mode=help ;;
  --patch | --minor | --major) release_set_bump "${1#--}" ;;
  v*)
    [[ -z $tag && -z $bump ]] || {
      release_fail 'Specify one version or bump.'
      return
    }
    tag=${1:?}
    ;;
  *) release_fail 'Expected --patch, --minor, --major, or a v-prefixed semantic version.' ;;
  esac
}

release_set_bump() {
  [[ -z $tag && -z $bump ]] || {
    release_fail 'Specify one version or bump.'
    return
  }
  bump=${1:?}
}

release_preflight() {
  release_require_clean_main || return
  local source_repo
  gh auth status >/dev/null 2>&1 || {
    release_fail 'Authenticate GitHub CLI before releasing.'
    return
  }
  source_repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner) || return
  [[ $source_repo == "$repo" ]] || {
    release_fail 'Wrong source repository.'
    return
  }
  release_check_ci
}

release_require_clean_main() {
  local remote_main
  [[ -z $(git status --porcelain) ]] || {
    release_fail 'Commit and merge changes before releasing.'
    return
  }
  [[ $(git branch --show-current) == main ]] || {
    release_fail 'Release from main.'
    return
  }
  git fetch --quiet origin main --tags || return
  remote_main=$(git rev-parse origin/main) || return
  [[ $remote_main == "$revision" ]] || release_fail 'Local main must match origin/main.'
}

release_select() {
  [[ -z $tag ]] || return 0
  if [[ -n ${bump:-} ]]; then
    release_select_bump
    return
  fi
  if [[ $mode == preview ]]; then
    tag="v$(<VERSION)"
    return
  fi
  release_select_interactive
}

release_select_bump() {
  local current
  current=$(git -c versionsort.suffix=- tag --list 'v*' --sort=-version:refname |
    sed -nE '/^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/ {p;q;}') || return
  tag=$(release_next_version "${current:-v0.0.0}" "$bump")
}

release_next_version() {
  local current=${1:?} kind=${2:?} major minor patch
  IFS=. read -r major minor patch <<<"${current#v}"
  case "$kind" in
  patch) printf 'v%s.%s.%s' "$major" "$minor" "$((patch + 1))" ;;
  minor) printf 'v%s.%s.0' "$major" "$((minor + 1))" ;;
  major) printf 'v%s.0.0' "$((major + 1))" ;;
  *) release_fail 'Unknown version bump.' ;;
  esac
}

release_select_interactive() {
  local current candidate
  current=$(git -c versionsort.suffix=- tag --list 'v*' --sort=-version:refname | sed -n '1p') || return
  current=${current:-v0.0.0}
  candidate=$(release_candidate "$current") || return
  printf 'Current: %s\n1) %s (recommended)\n2) custom version\n' "$current" "$candidate"
  release_prompt_choice "$candidate" || return
  release_validate_tag "$tag"
}

release_prompt_choice() {
  local candidate=${1:?} choice
  read -r -p 'Choose a version [1]: ' choice || return
  case "${choice:-1}" in
  1) tag=$candidate ;;
  2) read -r -p 'Version (vX.Y.Z or vX.Y.Z-rc.N): ' tag ;;
  *) release_fail 'Unknown version choice.' ;;
  esac
}

release_candidate() {
  local current=${1:?} core major minor _patch suffix
  core=${current#v}
  core=${core%%-*}
  IFS=. read -r major minor _patch <<<"$core"
  case "$current" in
  *-rc.*)
    suffix=${current##*-rc.}
    [[ $suffix =~ ^(0|[1-9][0-9]*)$ ]] || return 1
    printf 'v%s-rc.%s' "$core" "$((suffix + 1))"
    ;;
  *) printf 'v%s.%s.0-rc.1' "$major" "$((minor + 1))" ;;
  esac
}

release_context() {
  release_validate_tag "$tag" || return
  version=${tag#v}
  output=${HNET_RELEASE_DIR:-"$repo_dir/dist"}
  [[ $output == /* ]] || output="$repo_dir/$output"
  export HNET_RELEASE_DIR="$output"
  notes="$output/hnet-$version-NOTES.md"
}

release_require_ready() {
  [[ $version != *-* ]] || return 0
  jq -e '.stable_release_ready == true' ops/clients/homebrew-hnet.json >/dev/null ||
    release_fail 'Stable release gates are incomplete; choose an rc tag.'
}

release_require_available() {
  local tags releases
  if git rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
    release_fail 'Local release tag already exists.'
    return
  fi
  tags=$(gh api --method GET "repos/$repo/git/matching-refs/tags/$tag" \
    --jq "map(select(.ref == \"refs/tags/$tag\")) | length") || return
  [[ $tags == 0 ]] || {
    release_fail 'Remote release tag already exists.'
    return
  }
  releases=$(gh api --method GET --paginate --slurp "repos/$repo/releases?per_page=100") || return
  jq -e --arg tag "$tag" '[.[][] | select(.tag_name == $tag)] | length == 0' <<<"$releases" >/dev/null ||
    release_fail 'GitHub release already exists.'
}

release_check_ci() {
  local checks
  checks=$(gh api --method GET --paginate --slurp "repos/$repo/commits/$revision/check-runs?per_page=100") || return
  jq -e '
    [.[] | .check_runs[] | select(.app.id == 15368)] as $checks |
    ["validate", "macos-client"] | all(
      . as $name | [$checks[] | select(.name == $name)] | max_by(.id) |
      .status == "completed" and .conclusion == "success"
    )' <<<"$checks" >/dev/null || release_fail 'Latest Linux and macOS Actions checks must pass.'
}

release_build() {
  env -u HNET_RELEASE_VERSION "$repo_dir/tests/ops/clients/release_test.sh" || return
  "$repo_dir/ops/scripts/secret-scan.sh" || return
  HNET_RELEASE_VERSION="$version" "$repo_dir/ops/apps/hnetctl/hnetctl" release-bundle || return
  HNET_RELEASE_VERSION="$version" "$repo_dir/ops/scripts/verify-release-assets.sh" "$output" || return
  release_notes
}

release_notes() {
  cat >"$notes" <<EOF || return
# hnet $version

Built from commit $revision for trusted Macs using Codex and Claude Code.
Source tree: $source_state.
Applications and container images are separate prerequisites. Enrollment is explicit.

Buffered telemetry has no enforced 24-hour expiry. Backup expiry requires explicit
maintenance. Installing this release does not change running retention policies.
EOF
  if [[ $version == *-* ]]; then
    cat >>"$notes" <<'EOF'

This is an unsupported release candidate.
EOF
  fi
}

release_confirm() {
  local answer
  printf 'Selected %s at %s\n' "$tag" "$revision"
  read -r -p 'Tag, push, and dispatch release.yml? [y/N] ' answer || return
  [[ $answer == y || $answer == Y ]] || release_fail 'Release canceled.'
}

release_dispatch() {
  [[ -z $(git status --porcelain) && $(git rev-parse HEAD) == "$revision" ]] ||
    {
      release_fail 'Source changed during preparation.'
      return
    }
  git tag "$tag" "$revision" || return
  git push origin "refs/tags/$tag" || return
  gh workflow run release.yml --repo "$repo" --ref "$tag" --field "tag_name=$tag" ||
    {
      release_fail 'Tag pushed; workflow dispatch failed. Dispatch release.yml for that tag manually.'
      return
    }
  printf 'Dispatched release.yml for %s. Stable releases continue to Homebrew automatically.\n' "$tag"
}

release_source_revision() {
  local release_tag=${1:?} workflow_ref=${2:?} dispatch_revision=${3:?} source_revision
  release_validate_tag "$release_tag" || return
  [[ $workflow_ref == "refs/tags/$release_tag" ]] || {
    release_fail 'Dispatch from the release tag.'
    return
  }
  source_revision=$(git rev-parse HEAD) || return
  [[ $source_revision == "$dispatch_revision" ]] || {
    release_fail 'Release tag changed during dispatch.'
    return
  }
  git merge-base --is-ancestor "$source_revision" origin/main || {
    release_fail 'Release commit must belong to main.'
    return
  }
  printf '%s' "$source_revision"
}

release_validate_tag() {
  local pattern='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'
  [[ ${1:?} =~ $pattern ]] || release_fail 'Expected a v-prefixed semantic version.'
}

release_fail() {
  echo "$1" >&2
  return 1
}

release_entry "$@"
