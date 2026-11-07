#!/usr/bin/env bash

set -euo pipefail

main() (
  umask 077
  require_gitleaks
  local root stage
  root=$(cd -- "${BASH_SOURCE[0]%/*}/../.." && pwd)
  cd "$root"
  mkdir -p tmp
  stage=$(mktemp -d tmp/hnet-scan.XXXXXX)
  trap 'rm -rf -- "$stage"' EXIT
  stage_scan_inputs "$stage"
  gitleaks git --redact=100 --no-banner --log-opts=--all . >"$stage/history.log" 2>&1 || scan_failed history "$stage"
  gitleaks dir --redact=100 --no-banner "$stage/source" >"$stage/source.log" 2>&1 || scan_failed source "$stage"
  echo "Gitleaks passed for local reachable history and nonignored publication inputs. Hosted surfaces remain separate."
)

require_gitleaks() {
  command -v gitleaks >/dev/null 2>&1 || {
    echo "Gitleaks 8.30.1 is required; install the pinned project tool before publication." >&2
    exit 1
  }
  [[ $(gitleaks version) == 8.30.1 ]] || {
    echo "Use the pinned Gitleaks 8.30.1 version." >&2
    exit 1
  }
}

stage_scan_inputs() {
  local stage=${1:?} relative target
  mkdir -p "$stage/source"
  git ls-files --cached --others --exclude-standard -z >"$stage/files" || scan_failed input "$stage"
  while IFS= read -r -d '' relative; do
    [[ ! -L $relative ]] || scan_failed input "$stage"
    [[ -e $relative ]] || continue
    [[ -f $relative && ! -L $relative ]] || scan_failed input "$stage"
    target="$stage/source/$relative"
    mkdir -p "${target%/*}"
    cp "$relative" "$target"
  done <"$stage/files"
}

scan_failed() {
  local reason=${1:?} stage=${2:?} log
  for log in "$stage"/*.log; do
    [[ ! -f $log ]] || cp "$log" "tmp/publication-${log##*/}"
  done
  echo "Gitleaks $reason gate failed. Review redacted findings privately; publication remains blocked." >&2
  exit 1
}

main
