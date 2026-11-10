#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=tests/ops/test_support.sh
source "${BASH_SOURCE[0]%/*}/../test_support.sh"
# shellcheck source=ops/scripts/release.sh
_HNET_RELEASE_SOURCED=true source "$repo_dir/ops/scripts/release.sh"

main() {
  test_version_selection
  test_version_bumps
  test_bump_selection
  test_conflicting_versions
  test_stable_release_preferred
  test_preview_and_dry_run
  test_release_guards
  test_prepare_fails_closed
  test_available_version
  test_latest_ci_failure
  test_tag_push_dispatch
  test_frozen_release_source
  test_invalid_release_source
  test_unreviewed_release_source
  test_signature_policy
  echo 'Release selection, guards, dispatch, and signature policy tests passed.'
}

test_version_selection() (
  local tag='' mode='' bump=''
  release_parse --dry-run v0.2.0-rc.1
  [[ $mode == dry-run && $tag == v0.2.0-rc.1 ]]
  release_validate_tag v1.0.0
  if release_validate_tag v01.0.0 >/dev/null 2>&1; then fail 'Accepted leading zero.'; fi
  if release_validate_tag 'v0.2.0;bad' >/dev/null 2>&1; then fail 'Accepted invalid tag.'; fi
  [[ $(release_candidate v0.1.0) == v0.2.0-rc.1 ]]
  [[ $(release_candidate v0.2.0-rc.2) == v0.2.0-rc.3 ]]
  [[ $(release_candidate v1.2.3) == v1.3.0-rc.1 ]]
  git() { echo v0.1.0; }
  tag=''
  mode=publish
  release_select <<<'' >/dev/null
  [[ $tag == v0.2.0-rc.1 ]]
)

test_version_bumps() (
  [[ $(release_next_version v0.1.1 patch) == v0.1.2 ]]
  [[ $(release_next_version v0.1.1 minor) == v0.2.0 ]]
  [[ $(release_next_version v0.1.1 major) == v1.0.0 ]]
  [[ $(release_next_version v1.9.9 patch) == v1.9.10 ]]
  [[ $(release_next_version v1.9.9 minor) == v1.10.0 ]]
  [[ $(release_next_version v1.9.9 major) == v2.0.0 ]]
  if release_next_version v0.1.1 invalid >/dev/null 2>&1; then fail 'Accepted unknown bump.'; fi
)

test_bump_selection() (
  local tag='' mode='' bump=''
  git() { printf '%s\n' v2.0.0-rc.1 v1.10.0 v1.9.9; }
  release_parse --patch --dry-run
  release_select
  [[ $mode == dry-run && $tag == v1.10.1 ]]
  release_parse --minor
  release_select
  [[ $tag == v1.11.0 ]]
  release_parse --major
  release_select
  [[ $tag == v2.0.0 ]]
  git() { echo v0.1.0-rc.1; }
  release_parse --patch
  release_select
  [[ $tag == v0.0.1 ]]
)

test_conflicting_versions() (
  if release_parse --patch --minor >/dev/null 2>&1; then fail 'Accepted two bumps.'; fi
  if release_parse --patch v0.2.0 >/dev/null 2>&1; then fail 'Accepted bump then tag.'; fi
  if release_parse v0.2.0 --patch >/dev/null 2>&1; then fail 'Accepted tag then bump.'; fi
)

test_stable_release_preferred() (
  local tag='' mode=publish
  git() {
    local sorting="${1:-} ${2:-}"
    if [[ $sorting == '-c versionsort.suffix=-' ]]; then
      printf '%s\n' v0.2.0 v0.2.0-rc.2
      return
    fi
    printf '%s\n' v0.2.0-rc.2 v0.2.0
  }
  release_select <<<'' >/dev/null
  [[ $tag == v0.3.0-rc.1 ]] || fail 'Picker continued an already-stable release candidate.'
)

test_preview_and_dry_run() (
  local tag='' mode='' bump=''
  release_build() { :; }
  release_dispatch() { fail 'Preview dispatched a workflow.'; }
  git() { if [[ ${1:-} == -c ]]; then echo v0.1.1; else command git "$@"; fi; }
  release_preflight() { fail 'Offline preview reached GitHub.'; }
  release_main --preview v0.2.0-rc.1 >/dev/null
  release_preflight() { :; }
  release_require_available() { :; }
  release_main --dry-run v0.2.0-rc.1 >/dev/null
  release_main --patch --dry-run >/dev/null
  [[ $tag == v0.1.2 ]]
  release_main --major --dry-run >/dev/null
  [[ $tag == v1.0.0 ]]
)

test_release_guards() (
  jq() { return 1; }
  version=0.2.0
  if release_require_ready >/dev/null 2>&1; then fail 'Stable gate was bypassed.'; fi
  version=0.2.0-rc.1
  release_require_ready
  jq() { return 0; }
  version=0.2.0
  release_require_ready
  git() { if [[ $1 == status ]]; then echo changed; else fail 'Dirty preflight continued.'; fi; }
  if release_preflight >/dev/null 2>&1; then fail 'Dirty source accepted.'; fi
  git() { return 1; }
  gh() { return 1; }
  tag=v0.2.0-rc.1
  repo=yowainwright/hnet
  if release_require_available >/dev/null 2>&1; then fail 'Network error treated as unused tag.'; fi
  git() { return 0; }
  if release_require_available >/dev/null 2>&1; then fail 'Existing local tag accepted.'; fi
)

test_prepare_fails_closed() (
  local unexpected="$test_root/unexpected-git"
  mode=preview
  jq() { return 1; }
  git() {
    : >"$unexpected"
    return 1
  }
  if release_prepare >/dev/null 2>&1; then fail 'Metadata error accepted.'; fi
  [[ ! -e $unexpected ]] || fail 'Metadata failure reached Git operations.'
)

test_latest_ci_failure() (
  repo=yowainwright/hnet
  revision=example
  gh() { echo '[{"check_runs":[{"id":1,"name":"validate","status":"completed","conclusion":"success","app":{"id":15368}},{"id":2,"name":"macos-client","status":"completed","conclusion":"success","app":{"id":15368}},{"id":3,"name":"validate","status":"completed","conclusion":"failure","app":{"id":15368}}]}]'; }
  if release_check_ci >/dev/null 2>&1; then fail 'Stale passing CI accepted.'; fi
)

test_available_version() (
  revision=example
  repo=yowainwright/hnet
  tag=v0.2.0-rc.1
  git() { return 1; }
  gh() {
    case "$*" in
    *matching-refs*) echo 0 ;;
    *releases*) echo '[[]]' ;;
    *) return 1 ;;
    esac
  }
  release_require_available
  gh() { if [[ $* == *matching-refs* ]]; then echo 0; else echo '[[{"tag_name":"v0.2.0-rc.1"}]]'; fi; }
  if release_require_available >/dev/null 2>&1; then fail 'Existing GitHub release accepted.'; fi
  if release_confirm <<<'n' >/dev/null 2>&1; then fail 'Release proceeded without confirmation.'; fi
)

test_tag_push_dispatch() (
  local log="$test_root/dispatch.log"
  revision=example
  tag=v0.2.0-rc.1
  repo=yowainwright/hnet
  git() {
    case "$1" in
    status) ;;
    rev-parse) echo example ;;
    *) printf 'git %s\n' "$*" >>"$log" ;;
    esac
  }
  gh() { printf 'gh %s\n' "$*" >>"$log"; }
  release_dispatch >/dev/null
  grep -Fxq 'git tag v0.2.0-rc.1 example' "$log"
  grep -Fxq 'git push origin refs/tags/v0.2.0-rc.1' "$log"
  grep -Fxq 'gh workflow run release.yml --repo yowainwright/hnet --ref v0.2.0-rc.1 --field tag_name=v0.2.0-rc.1' "$log"
)

test_frozen_release_source() (
  frozen_source_git
  [[ $(git rev-parse origin/main) != frozen ]]
  local source
  source=$(release_source_revision v0.2.0-rc.1 refs/tags/v0.2.0-rc.1 frozen)
  [[ $source == frozen ]] || fail 'Advancing main blocked the reviewed release commit.'
)

test_invalid_release_source() (
  frozen_source_git
  if release_source_revision v0.2.0-rc.1 refs/heads/main frozen >/dev/null 2>&1; then
    fail 'Release accepted a branch dispatch.'
  fi
  if release_source_revision v0.2.0-rc.1 refs/tags/v0.2.0-rc.1 changed >/dev/null 2>&1; then
    fail 'Release accepted a changed tag.'
  fi
)

test_unreviewed_release_source() (
  git() { if [[ ${1:-} == rev-parse ]]; then echo frozen; else return 1; fi; }
  if release_source_revision v0.2.0-rc.1 refs/tags/v0.2.0-rc.1 frozen >/dev/null 2>&1; then
    fail 'Release accepted a commit outside main.'
  fi
)

frozen_source_git() {
  git() {
    case "$*" in
    'rev-parse HEAD') echo frozen ;;
    'rev-parse origin/main') echo advanced ;;
    'merge-base --is-ancestor frozen origin/main') return 0 ;;
    *) return 1 ;;
    esac
  }
}

test_signature_policy() (
  local assets="$test_root/signature" fake_bin="$test_root/bin" log="$test_root/cosign.log"
  mkdir -p "$assets" "$fake_bin"
  printf 'checksums\n' >"$assets/hnet-0.2.0-rc.1-SHA256SUMS"
  printf 'bundle\n' >"$assets/hnet-0.2.0-rc.1-SHA256SUMS.bundle"
  cat >"$fake_bin/cosign" <<'TOOL'
#!/usr/bin/env bash
printf '%s\n' "$@" >"${HNET_TEST_COSIGN_LOG:?}"
TOOL
  chmod +x "$fake_bin/cosign"
  PATH="$fake_bin:$PATH" HNET_TEST_COSIGN_LOG="$log" HNET_RELEASE_VERSION=0.2.0-rc.1 \
    "$repo_dir/ops/scripts/verify-checksum-signature.sh" "$assets"
  grep -Fxq 'https://github.com/yowainwright/hnet/.github/workflows/release.yml@refs/tags/v0.2.0-rc.1' "$log"
  grep -Fxq 'https://token.actions.githubusercontent.com' "$log"
)

main
