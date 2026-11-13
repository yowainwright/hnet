#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd -- "${BASH_SOURCE[0]%/*}" && pwd)
repo_dir=$(cd -- "$script_dir/../.." && pwd)
paths=()
bash_files=()
source_files=()

main() {
  cd "$repo_dir"
  require_tools
  collect_paths
  fs-lint check -- "${paths[@]}"
  check_imports
  check_declaration_order
}

require_tools() {
  local tool
  for tool in fs-lint src-lint struct-lint; do
    command -v "$tool" >/dev/null 2>&1 || {
      echo "Missing $tool; install the pinned tools with mise install." >&2
      exit 1
    }
  done
}

collect_paths() {
  local path
  while IFS= read -r -d '' path; do
    [[ -f $path ]] || continue
    [[ ! -L $path ]] || {
      echo "Lint inputs must be regular repository files." >&2
      exit 1
    }
    paths+=("$path")
    case "$path" in
    *.sh | *.bash) bash_files+=("$path") ;;
    *.js | *.jsx | *.mjs | *.cjs | *.ts | *.tsx | *.mts | *.cts | *.py | *.go | *.proto | *.jl | *.rb | *.swift | *.kt | *.kts | *.java | *.tf)
      source_files+=("$path")
      ;;
    esac
  done < <(git ls-files --cached --others --exclude-standard -z)
}

check_imports() {
  local path
  if ((${#source_files[@]} == 0)); then
    src-lint discover ops/apps --config .src-lintrc --format json >/dev/null
    echo "src-lint: no supported source files; Bash imports are outside its coverage."
    return
  fi
  for path in "${source_files[@]}"; do
    src-lint check "$path" --config .src-lintrc --strict
  done
}

check_declaration_order() (
  local scratch result=0
  mkdir -p "$repo_dir/tmp"
  scratch=$(mktemp -d "$repo_dir/tmp/struct-lint.XXXXXX")
  trap 'rm -rf "$scratch"' EXIT
  cp ops/apps/hnetctl/hnetctl "$scratch/hnetctl.sh"
  struct-lint --profile ci "${bash_files[@]}" "$scratch/hnetctl.sh" 2>"$scratch/diagnostics" || result=$?
  sed "s|$scratch/hnetctl.sh|ops/apps/hnetctl/hnetctl|g" "$scratch/diagnostics" >&2
  exit "$result"
)

main "$@"
