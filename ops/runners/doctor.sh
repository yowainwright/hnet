#!/usr/bin/env bash

set -euo pipefail

runner_root=${HNET_RUNNER_ROOT:-"$HOME/.hnet/runners"}
repo=${HNET_RUNNER_REPO:-}
expected_labels=${HNET_RUNNER_LABELS:-self-hosted,macos,ci,hnet-ci}
failures=0

usage() {
  cat <<'USAGE'
Usage: doctor.sh [options]

Options:
  --repo OWNER/REPO       Check one repository runner
  --runner-root PATH      Runner storage; defaults to ~/.hnet/runners
  --labels LABELS         Labels expected on the GitHub runner
  --help                  Show this help
USAGE
}

warn() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

check_command() {
  command -v "$1" >/dev/null 2>&1 || warn "missing command: $1"
}

validate_repo() {
  local owner repo_name
  owner=${repo%%/*}
  repo_name=${repo#*/}
  if [[ $repo != */* || -z $owner || -z $repo_name || $repo_name == */* ]]; then
    warn "repository must use OWNER/REPO format: $repo"
    return 1
  fi
  case "$owner$repo_name" in
  *[!A-Za-z0-9_.-]*)
    warn "repository contains unsupported characters: $repo"
    return 1
    ;;
  esac
}

repo_key() {
  printf '%s\n' "${1//\//-}"
}

check_labels() {
  local actual_labels=$1 label
  local old_ifs=$IFS
  IFS=,
  read -r -a required_labels <<<"$expected_labels"
  IFS=$old_ifs
  for label in "${required_labels[@]}"; do
    case ",$actual_labels," in
    *,"$label",*) ;;
    *) warn "runner is missing label '$label'" ;;
    esac
  done
}

check_runner() {
  local runner_dir=$1 runner_repo runner_name remote_runners runner_line
  local service_output service_ok=false line
  [[ -d $runner_dir ]] || {
    warn "runner directory is missing: $runner_dir"
    return
  }
  if [[ ! -f "$runner_dir/.runner" ]]; then
    warn "runner is not configured: $runner_dir"
  fi
  [[ -x "$runner_dir/svc.sh" ]] || {
    warn "runner service script is missing: $runner_dir/svc.sh"
    return
  }
  runner_repo=$repo
  if [[ -z $runner_repo && -f "$runner_dir/.hnet-repo" ]]; then
    runner_repo=$(<"$runner_dir/.hnet-repo")
  fi
  [[ -n $runner_repo ]] || warn "runner repository metadata is missing: $runner_dir"
  runner_name=
  if [[ -f "$runner_dir/.runner" ]]; then
    runner_name=$(sed -n 's/.*"agentName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
      "$runner_dir/.runner" | head -n 1)
  fi
  if [[ -z $runner_name ]]; then
    warn "runner name is missing: $runner_dir/.runner"
  fi

  if service_output=$(cd "$runner_dir" && ./svc.sh status 2>&1); then
    service_ok=true
  fi
  printf '%s\n' "$service_output"
  [[ $service_ok == true ]] || warn "launchd service is not healthy: $runner_dir"

  [[ -n $runner_repo ]] || return
  if ! remote_runners=$(gh api "repos/$runner_repo/actions/runners" \
    --jq '.runners[] | [.name, .status, (.busy | tostring), ([.labels[].name] | join(","))] | join("\t")'); then
    warn "could not inspect GitHub runners for $runner_repo"
    return
  fi
  runner_line=
  while IFS= read -r line; do
    case "$line" in
    "$runner_name"$'\t'*)
      runner_line=$line
      break
      ;;
    esac
  done <<<"$remote_runners"
  [[ -n $runner_line ]] || {
    warn "runner is not registered on GitHub: $runner_name"
    return
  }
  printf 'GitHub runner: %s\n' "$runner_line"
  case "$runner_line" in
  *$'\tonline\t'*) ;;
  *) warn "runner is not online: $runner_name" ;;
  esac
  check_labels "${runner_line##*$'\t'}"
}

while (($# > 0)); do
  case "$1" in
  --repo)
    [[ $# -ge 2 ]] || {
      warn "--repo requires OWNER/REPO"
      break
    }
    repo=$2
    shift 2
    ;;
  --runner-root)
    [[ $# -ge 2 ]] || {
      warn "--runner-root requires a path"
      break
    }
    runner_root=$2
    shift 2
    ;;
  --labels)
    [[ $# -ge 2 ]] || {
      warn "--labels requires a comma-separated list"
      break
    }
    expected_labels=$2
    shift 2
    ;;
  --help)
    usage
    exit 0
    ;;
  *)
    warn "unknown option: $1"
    shift
    ;;
  esac
done

[[ $(uname -s) == Darwin ]] || warn "self-hosted Mac runners require macOS"
for command_name in gh curl tar launchctl shellcheck shfmt helm zsh docker; do
  check_command "$command_name"
done
if command -v docker >/dev/null 2>&1; then
  docker compose version >/dev/null 2>&1 || warn "docker compose is unavailable"
fi
if command -v gh >/dev/null 2>&1; then
  gh auth status >/dev/null 2>&1 || warn "authenticate GitHub CLI: gh auth login"
fi

if [[ -n $repo ]]; then
  if validate_repo; then
    check_runner "$runner_root/$(repo_key "$repo")"
  fi
elif [[ -d $runner_root ]]; then
  runner_found=false
  while IFS= read -r runner_dir; do
    runner_found=true
    check_runner "$runner_dir"
  done < <(find "$runner_root" -mindepth 1 -maxdepth 1 -type d ! -name '.download.*' -print | sort)
  [[ $runner_found == true ]] || warn "no runner directories found under $runner_root"
else
  warn "runner root is missing: $runner_root"
fi

if ((failures > 0)); then
  echo "Runner doctor found $failures problem(s)." >&2
  exit 1
fi
echo "Runner doctor passed."
