#!/usr/bin/env bash

set -euo pipefail
umask 077

script_path=${BASH_SOURCE[0]}
script_dir=$(cd -- "${script_path%/*}" && pwd)
repo_dir=$(cd -- "$script_dir/../.." && pwd)
runner_root=${HNET_RUNNER_ROOT:-"$HOME/.hnet/runners"}
repo=${HNET_RUNNER_REPO:-}
runner_name=${HNET_RUNNER_NAME:-}
labels=${HNET_RUNNER_LABELS:-self-hosted,macos,ci,hnet-ci}
replace=false
dry_run=false
install_deps=false
registration_token=
removal_token=
download_dir=

usage() {
  cat <<'USAGE'
Usage: setup.sh [options]

Options:
  --repo OWNER/REPO       Repository to register; defaults to the current repo
  --runner-root PATH      Runner storage; defaults to ~/.hnet/runners
  --runner-name NAME      Runner name; defaults to hnet-HOST-OWNER-REPO
  --labels LABELS         Comma-separated runner labels
  --replace               Replace an existing runner with the same repo
  --install-deps          Install the Brewfile before setup
  --dry-run               Validate inputs and show the setup plan
  --help                  Show this help
USAGE
}

fail() {
  echo "$1" >&2
  exit "${2:-1}"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

validate_repo() {
  local owner repo_name
  owner=${repo%%/*}
  repo_name=${repo#*/}
  [[ -n $owner && -n $repo_name && $repo_name != */* ]] ||
    fail "Repository must use OWNER/REPO format: $repo"
  case "$owner$repo_name" in
  *[!A-Za-z0-9_.-]*) fail "Repository contains unsupported characters: $repo" ;;
  esac
}

validate_labels() {
  [[ -n $labels ]] || fail "Runner labels cannot be empty."
  case "$labels" in
  *[[:space:]]*) fail "Runner labels cannot contain whitespace." ;;
  esac
}

validate_runner_name() {
  [[ -n $runner_name ]] || fail "Runner name cannot be empty."
  case "$runner_name" in
  *[!A-Za-z0-9_.-]*) fail "Runner name contains unsupported characters: $runner_name" ;;
  esac
}

validate_runner_root() {
  [[ $runner_root == /* ]] || fail "Runner root must be an absolute path: $runner_root"
  [[ $runner_root != / && $runner_root != "$repo_dir" && $runner_root != "$repo_dir"/* ]] ||
    fail "Runner root must be outside this repository: $runner_root"
}

cleanup() {
  registration_token=
  removal_token=
  if [[ -n $download_dir && -d $download_dir ]]; then
    rm -rf "$download_dir"
  fi
}

remove_existing_runner() {
  local runner_dir=$1
  if [[ -x "$runner_dir/svc.sh" ]]; then
    (cd "$runner_dir" && ./svc.sh stop >/dev/null 2>&1 || true)
    (cd "$runner_dir" && ./svc.sh uninstall >/dev/null 2>&1 || true)
  fi
  removal_token=$(gh api --method POST \
    "repos/$repo/actions/runners/remove-token" --jq '.token')
  [[ -n $removal_token && $removal_token != null ]] ||
    fail "GitHub did not return a runner removal token."
  (cd "$runner_dir" && ./config.sh remove --unattended --token "$removal_token")
  rm -rf "$runner_dir"
  removal_token=
}

resolve_repo() {
  [[ -n $repo ]] && return
  repo=$(gh repo view --json nameWithOwner --jq '.nameWithOwner')
}

setup_runner() {
  local repo_key runner_dir host_name release_tag version asset_name asset_url archive
  local staging_dir
  repo_key=${repo//\//-}
  runner_dir="$runner_root/$repo_key"
  host_name=$(hostname -s 2>/dev/null || hostname)
  runner_name=${runner_name:-hnet-${host_name}-${repo_key}}
  validate_runner_root
  validate_labels
  validate_runner_name

  if [[ -e $runner_dir || -L $runner_dir ]]; then
    if [[ $replace != true ]]; then
      [[ -f "$runner_dir/.runner" ]] ||
        fail "Runner path exists but is not configured: $runner_dir"
      echo "Runner already configured: $runner_dir"
      echo "Use --replace only when replacement is intentional."
      return
    fi
    if [[ $dry_run == true ]]; then
      echo "Would replace runner: $runner_dir"
      return
    fi
    remove_existing_runner "$runner_dir"
  fi

  if [[ $dry_run == true ]]; then
    echo "Would register $repo as $runner_name"
    echo "Would use labels: $labels"
    echo "Would install under: $runner_dir"
    echo "Would install and start the launchd service."
    return
  fi

  mkdir -p "$runner_root"
  download_dir=$(mktemp -d "$runner_root/.download.XXXXXX")
  archive="$download_dir/runner.tar.gz"
  release_tag=$(gh api repos/actions/runner/releases/latest --jq '.tag_name')
  version=${release_tag#v}
  case "$(uname -m)" in
  arm64) asset_name="actions-runner-osx-arm64-${version}.tar.gz" ;;
  x86_64) asset_name="actions-runner-osx-x64-${version}.tar.gz" ;;
  *) fail "Unsupported macOS architecture: $(uname -m)" ;;
  esac
  asset_url="https://github.com/actions/runner/releases/download/$release_tag/$asset_name"
  curl --fail --silent --show-error --location --retry 3 \
    --output "$archive" "$asset_url"
  staging_dir="$download_dir/runner"
  mkdir -p "$staging_dir"
  tar -xzf "$archive" -C "$staging_dir"
  mv "$staging_dir" "$runner_dir"

  registration_token=$(gh api --method POST \
    "repos/$repo/actions/runners/registration-token" --jq '.token')
  [[ -n $registration_token && $registration_token != null ]] ||
    fail "GitHub did not return a runner registration token."
  (
    cd "$runner_dir"
    ./config.sh --unattended --url "https://github.com/$repo" \
      --token "$registration_token" --name "$runner_name" \
      --labels "$labels" --work _work
  )
  registration_token=
  printf '%s\n' "$repo" >"$runner_dir/.hnet-repo"
  chmod 600 "$runner_dir/.hnet-repo"
  (
    cd "$runner_dir"
    ./svc.sh install
    ./svc.sh start
  )
  echo "Runner ready: $runner_name"
  echo "Repository: $repo"
  echo "Labels: $labels"
  echo "Directory: $runner_dir"
}

while (($# > 0)); do
  case "$1" in
  --repo)
    [[ $# -ge 2 ]] || fail "--repo requires OWNER/REPO"
    repo=$2
    shift 2
    ;;
  --runner-root)
    [[ $# -ge 2 ]] || fail "--runner-root requires a path"
    runner_root=$2
    shift 2
    ;;
  --runner-name)
    [[ $# -ge 2 ]] || fail "--runner-name requires a name"
    runner_name=$2
    shift 2
    ;;
  --labels)
    [[ $# -ge 2 ]] || fail "--labels requires a comma-separated list"
    labels=$2
    shift 2
    ;;
  --replace)
    replace=true
    shift
    ;;
  --install-deps)
    install_deps=true
    shift
    ;;
  --dry-run)
    dry_run=true
    shift
    ;;
  --help)
    usage
    exit 0
    ;;
  *)
    fail "Unknown option: $1"
    ;;
  esac
done

[[ $dry_run != true || $install_deps != true ]] ||
  fail "--dry-run cannot be combined with --install-deps."
trap cleanup EXIT

[[ $(uname -s) == Darwin ]] || fail "Self-hosted Mac runners require macOS."
if [[ $install_deps == true ]]; then
  require_command brew
  brew bundle --file "$script_dir/Brewfile"
fi
require_command gh
require_command curl
require_command tar
require_command launchctl
if [[ $dry_run != true || -z $repo ]]; then
  gh auth status >/dev/null 2>&1 || fail "Authenticate GitHub CLI before setup: gh auth login"
fi
resolve_repo
validate_repo
setup_runner
