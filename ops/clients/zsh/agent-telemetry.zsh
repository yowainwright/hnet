autoload -Uz add-zsh-hook
zmodload zsh/datetime

if [[ -n "${_AGENT_TELEMETRY_LOADED:-}" ]]; then
  return 0
fi

typeset -g _AGENT_TELEMETRY_LOADED=1
typeset -g _AGENT_TELEMETRY_CATEGORY=""
typeset -g _AGENT_TELEMETRY_PROJECT="unlabeled"
typeset -gF _AGENT_TELEMETRY_STARTED=0

_agent_telemetry_safe_label() {
  local label="$1"
  [[ "$label" == [A-Za-z0-9]* ]] || return 1
  [[ "$label" != *[^A-Za-z0-9._-]* ]] || return 1
  print -r -- "$label"
}

_agent_telemetry_category() {
  local -a words
  words=(${(z)1})
  local executable="${words[1]:t}"

  case "$executable" in
    git|gh|docker|docker-compose|npm|pnpm|bun|nub|node|python|python3|pytest|uv|cargo|rustc|go|mise|make|just|curl|ssh|rsync|brew|npx|yarn|deno)
      print -r -- "$executable"
      ;;
    *.sh|*.zsh|bash|zsh|sh)
      print -r -- "script"
      ;;
    *)
      print -r -- "other"
      ;;
  esac
}

_agent_telemetry_preexec() {
  _AGENT_TELEMETRY_CATEGORY="$(_agent_telemetry_category "$1")"
  _AGENT_TELEMETRY_STARTED=$EPOCHREALTIME
}

_agent_telemetry_precmd() {
  local exit_code=$?
  [[ -n "$_AGENT_TELEMETRY_CATEGORY" ]] || return

  local duration_ms=$(( (EPOCHREALTIME - _AGENT_TELEMETRY_STARTED) * 1000 ))
  printf '{"event.name":"shell.command","shell.command.category":"%s","shell.duration_ms":%d,"shell.exit_code":%d,"shell.project":"%s"}\n' \
    "$_AGENT_TELEMETRY_CATEGORY" "$duration_ms" "$exit_code" "$_AGENT_TELEMETRY_PROJECT" >>"$_AGENT_TELEMETRY_FILE"
  _AGENT_TELEMETRY_CATEGORY=""
}

_agent_telemetry_init() {
  local state_root="${AGENT_TELEMETRY_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/agent-telemetry}"
  local project="${AGENT_TELEMETRY_PROJECT:-unlabeled}"

  _AGENT_TELEMETRY_PROJECT="$(_agent_telemetry_safe_label "$project")" || _AGENT_TELEMETRY_PROJECT="unlabeled"
  _AGENT_TELEMETRY_FILE="$state_root/zsh.jsonl"
  umask 077
  mkdir -p "$state_root"
  touch "$_AGENT_TELEMETRY_FILE"
  add-zsh-hook preexec _agent_telemetry_preexec
  add-zsh-hook precmd _agent_telemetry_precmd
}

_agent_telemetry_init
