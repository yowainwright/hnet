#!/usr/bin/env bash

set -euo pipefail

script_path=${BASH_SOURCE[0]}
script_parent=${script_path%/*}
script_dir=$(cd -- "$script_parent" && pwd)
repo_dir=$(cd -- "$script_dir/../.." && pwd)
format_mode=optional

case "${1:-}" in
'') ;;
--strict) format_mode=strict ;;
*)
  echo "Usage: $0 [--strict]" >&2
  exit 2
  ;;
esac

fail() {
  echo "$1" >&2
  exit "${2:-1}"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

cd "$repo_dir"
require_command shellcheck
require_command zsh

shell_files=()
while IFS= read -r shell_file; do
  shell_files+=("$shell_file")
done < <(find ops tests -type f -name '*.sh' -print | sort)

[[ ${#shell_files[@]} -gt 0 ]] || fail 'No shell files found.'

shellcheck -x "${shell_files[@]}"
zsh -n ops/clients/zsh/*.zsh

if command -v shfmt >/dev/null 2>&1; then
  shfmt -d "${shell_files[@]}"
elif [[ $format_mode == strict ]]; then
  fail "Missing required command: shfmt"
else
  echo "Warning: shfmt unavailable; skipping shell formatting." >&2
fi
