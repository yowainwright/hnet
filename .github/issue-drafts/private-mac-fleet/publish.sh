#!/usr/bin/env bash

set -euo pipefail

script_path=${BASH_SOURCE[0]}
bundle_dir=$(cd -- "${script_path%/*}" && pwd)
repo=${GH_REPO:-yowainwright/hnet}
publish=${1:-}
declare -a issue_urls issue_numbers

require_command() {
  command -v "$1" >/dev/null 2>&1 && return
  printf 'Missing required command: %s\n' "$1" >&2
  exit 1
}

preview() {
  local start_pattern end_pattern
  start_pattern='/^| Epic /'
  end_pattern='/^| 10 /p'
  sed -n "$start_pattern,$end_pattern" "$bundle_dir/README.md"
  printf '\nNo GitHub changes made. Pass --publish to publish to %s.\n' "$repo"
}

create_labels() {
  ensure_label epic 5319E7 "Tracks a coordinated group of issues"
  ensure_label needs-info FBCA04 "Blocked on a decision or required information"
  ensure_label needs-triage D4C5F9 "Needs scope and ownership review"
  ensure_label ready-for-review 1D76DB "Drafted and ready for human review"
  ensure_label ready-to-implement 0E8A16 "Approved and independently implementable"
}

ensure_label() {
  local name=$1 color=$2 description=$3 query existing
  query=".[] | select(.name == \"$name\") | .name"
  existing=$(gh label list -R "$repo" --limit 100 --json name --jq "$query")
  [[ $existing == "$name" ]] && return
  gh label create "$name" -R "$repo" --color "$color" \
    --description "$description"
}

publish_fleet_issues() {
  epic_title="Operate the private Mac fleet through Kubernetes, Tailscale, and Temporal"
  epic_url=$(create_epic "$epic_title")
  epic_number=${epic_url##*/}
  printf '#%s %s\n' "$epic_number" "$epic_title" >&2
  create_children
  printf 'Epic: %s\n' "$epic_url"
}

create_epic() {
  local title=$1 existing body_file
  existing=$(find_issue_url "$title")
  if [[ -n $existing ]]; then
    printf '%s\n' "$existing"
    return
  fi
  body_file="$bundle_dir/epic.md"
  gh issue create -R "$repo" --title "$title" --body-file "$body_file" \
    --label epic --label ready-for-review
}

create_children() {
  create_child 1 01-kubernetes-smoke.md "Operate a private Kubernetes smoke workload from remote k9s"
  create_child 2 02-synthetic-telemetry.md "Observe synthetic telemetry through Kubernetes" "${issue_numbers[1]}"
  create_child 3 03-durable-health-workflow.md "Run a durable health workflow from hnetctl" "${issue_numbers[1]}"
  create_child 4 04-telemetry-cutover.md "Build a reversible central telemetry cutover" "${issue_numbers[2]}"
  create_child 5 05-enroll-mac-worker.md "Enroll one Mac as a managed fleet endpoint" "${issue_numbers[3]},${issue_numbers[4]}"
  create_child 6 06-valkey-fleet-presence.md "Show fleet presence and capacity through Valkey" "${issue_numbers[5]}"
  create_child 7 07-recoverable-archive.md "Archive telemetry through a recoverable workflow" "${issue_numbers[3]},${issue_numbers[4]}"
  create_child 8 08-isolated-restore-drill.md "Prove an archive with an isolated restore drill" "${issue_numbers[7]}"
  create_child 9 09-approved-maintenance.md "Run an approved maintenance workflow on a managed Mac" "${issue_numbers[5]},${issue_numbers[7]}"
  create_child 10 10-control-plane-recovery.md "Recover the control plane without Temporal" "${issue_numbers[3]},${issue_numbers[8]}"
}

create_child() {
  local index=$1 file=$2 title=$3 blockers=${4:-} existing
  existing=$(find_issue_url "$title")
  if [[ -n $existing ]]; then
    issue_urls[index]=$existing
  else
    issue_urls[index]=$(publish_child "$file" "$title" "$blockers")
  fi
  issue_numbers[index]=${issue_urls[index]##*/}
  printf '#%s %s\n' "${issue_numbers[index]}" "$title" >&2
}

find_issue_url() {
  local title=$1 query
  query="[.[] | select(.title == \"$title\")][0].url // \"\""
  gh issue list -R "$repo" --state all --limit 1000 \
    --json title,url --jq "$query"
}

publish_child() {
  local file=$1 title=$2 blockers=$3 body_file
  body_file="$bundle_dir/$file"
  if [[ -n $blockers ]]; then
    render_body "$body_file" | gh issue create -R "$repo" --title "$title" \
      --body-file - --parent "$epic_number" --blocked-by "$blockers" \
      --label enhancement --label ready-for-review
    return
  fi
  render_body "$body_file" | gh issue create -R "$repo" --title "$title" \
    --body-file - --parent "$epic_number" \
    --label enhancement --label ready-for-review
}

render_body() {
  local source=$1 content token index replacement
  content=$(<"$source")
  content=${content//\{\{PARENT_URL\}\}/$epic_url}
  for index in {1..10}; do
    printf -v token '{{ISSUE_%02d_URL}}' "$index"
    replacement=${issue_urls[index]:-}
    content=${content//$token/$replacement}
  done
  printf '%s\n' "$content"
}

require_command gh
if [[ $publish != --publish ]]; then
  preview
  exit 0
fi

gh auth status >/dev/null
create_labels





publish_fleet_issues
