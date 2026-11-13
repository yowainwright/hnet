#!/usr/bin/env bash

set -euo pipefail

script_path=${BASH_SOURCE[0]}
script_dir=$(cd -- "${script_path%/*}" && pwd)
repo_dir=$(cd -- "$script_dir/../.." && pwd)
setup_script="$script_dir/setup.sh"
account=${HNET_GITHUB_ACCOUNT:-}
runner_root=${HNET_RUNNER_ROOT:-"$HOME/.hnet/runners"}
labels=
replace=false
dry_run=false
install_deps=false

main() {
  [[ $dry_run != true || $install_deps != true ]] ||
    fail "--dry-run cannot be combined with --install-deps."

  install_runner_dependencies
  require_command gh
  [[ -x $setup_script ]] || fail "Missing runner setup script: $setup_script"
  gh auth status >/dev/null 2>&1 || fail "Authenticate GitHub CLI before setup: gh auth login"
  account=${account:-$(gh api user --jq '.login')}

  private_repos=$(gh repo list "$account" --visibility private --limit 1000 \
    --json nameWithOwner,isArchived \
    --jq '.[] | select(.isArchived | not) | .nameWithOwner')
  [[ -n $private_repos ]] || {
    echo "No active private repositories found for $account."
    return 0
  }
  setup_private_repositories
}

usage() {
  cat <<'USAGE'
Usage: setup-all.sh [options]

Register one runner for every active private repository visible to the
authenticated GitHub account.

Options:
  --account ACCOUNT       GitHub account; defaults to the authenticated user
  --runner-root PATH      Runner storage; defaults to ~/.hnet/runners
  --labels LABELS         Comma-separated runner labels
  --replace               Replace existing runners
  --install-deps          Install CLI dependencies from mise.toml once
  --dry-run               Show the per-repository setup plan
  --help                  Show this help
USAGE
}

install_runner_dependencies() {
  [[ $install_deps == true ]] || return 0
  require_command mise
  mise -C "$repo_dir" install
  mise_paths=$(mise -C "$repo_dir" bin-paths | paste -sd ':' -)
  export PATH="$mise_paths:$PATH"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

fail() {
  echo "$1" >&2
  exit "${2:-1}"
}

setup_private_repositories() {
  repo_count=0
  while IFS= read -r repo; do
    [[ -n $repo ]] || continue
    repo_count=$((repo_count + 1))
    repo_args=(--repo "$repo" --runner-root "$runner_root")
    [[ -n $labels ]] && repo_args+=(--labels "$labels")
    [[ $replace == true ]] && repo_args+=(--replace)
    [[ $dry_run == true ]] && repo_args+=(--dry-run)
    echo "Setting up runner $repo_count: $repo"
    "$setup_script" "${repo_args[@]}"
  done <<<"$private_repos"

  echo "Prepared $repo_count private-repository runner(s)."
}

while (($# > 0)); do
  case "$1" in
  --account)
    [[ $# -ge 2 ]] || fail "--account requires a GitHub account"
    account=$2
    shift 2
    ;;
  --runner-root)
    [[ $# -ge 2 ]] || fail "--runner-root requires a path"
    runner_root=$2
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

main
