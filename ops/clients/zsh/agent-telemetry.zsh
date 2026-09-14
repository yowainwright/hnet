autoload -Uz add-zsh-hook
zmodload zsh/datetime

if [[ -n "${_AGENT_TELEMETRY_LOADED:-}" ]]; then
  return 0
fi

typeset -g _AGENT_TELEMETRY_LOADED=1
typeset -g _AGENT_TELEMETRY_CATEGORY=""
typeset -g _AGENT_TELEMETRY_PROJECT="unlabeled"
typeset -gF _AGENT_TELEMETRY_STARTED=0
typeset -gi _AGENT_TELEMETRY_SENDER_FD=-1
typeset -ga _AGENT_TELEMETRY_PENDING=()

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

_agent_telemetry_record() {
  local duration_ms=$1 exit_code=$2
  printf '{"attributes":[{"key":"event.name","value":{"stringValue":"shell.command"}},{"key":"shell.command.category","value":{"stringValue":"%s"}},{"key":"shell.duration_ms","value":{"intValue":"%d"}},{"key":"shell.exit_code","value":{"intValue":"%d"}},{"key":"shell.project","value":{"stringValue":"%s"}}],"body":{"stringValue":""}}' \
    "$_AGENT_TELEMETRY_CATEGORY" "$duration_ms" "$exit_code" "$_AGENT_TELEMETRY_PROJECT"
}

_agent_telemetry_send() {
  local records="${(j:,:)@}"
  local endpoint="${AGENT_TELEMETRY_LOCAL_ENDPOINT:-http://127.0.0.1:4318/v1/logs}"
  local token="${AGENT_TELEMETRY_INGEST_TOKEN:-}"
  [[ "$token" =~ '^[A-Za-z0-9._~-]{32,}$' ]] || return
  command -v curl >/dev/null 2>&1 || return

  local payload
  payload=$(printf '{"resourceLogs":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"hnet.zsh"}}]},"scopeLogs":[{"scope":{"name":"hnet.zsh"},"logRecords":[%s]}]}]}' "$records")
  printf 'header = "Authorization: Bearer %s"\n' "$token" |
    curl --config - --silent --show-error --fail --connect-timeout 1 --max-time 2 \
      --header 'Content-Type: application/json' --data-binary "$payload" "$endpoint" >/dev/null 2>&1 || true
}

_agent_telemetry_sender_done() {
  zle -F "$1"
  exec {_AGENT_TELEMETRY_SENDER_FD}<&-
  _AGENT_TELEMETRY_SENDER_FD=-1
  _agent_telemetry_flush
}

_agent_telemetry_flush() {
  (( _AGENT_TELEMETRY_SENDER_FD < 0 && ${#_AGENT_TELEMETRY_PENDING} > 0 )) || return 0
  exec {_AGENT_TELEMETRY_SENDER_FD}< <(
    _agent_telemetry_send "${_AGENT_TELEMETRY_PENDING[@]}" </dev/null >/dev/null 2>&1
  )
  _AGENT_TELEMETRY_PENDING=()
  zle -F "$_AGENT_TELEMETRY_SENDER_FD" _agent_telemetry_sender_done
}

_agent_telemetry_precmd() {
  local exit_code=$?
  [[ -n "$_AGENT_TELEMETRY_CATEGORY" ]] || return

  local duration_ms=$(( (EPOCHREALTIME - _AGENT_TELEMETRY_STARTED) * 1000 ))
  _AGENT_TELEMETRY_PENDING+=("$(_agent_telemetry_record "$duration_ms" "$exit_code")")
  _AGENT_TELEMETRY_CATEGORY=""
  _agent_telemetry_flush
}

_agent_telemetry_init() {
  local project="${AGENT_TELEMETRY_PROJECT:-unlabeled}"

  _AGENT_TELEMETRY_PROJECT="$(_agent_telemetry_safe_label "$project")" || _AGENT_TELEMETRY_PROJECT="unlabeled"
  add-zsh-hook preexec _agent_telemetry_preexec
  add-zsh-hook precmd _agent_telemetry_precmd
}

_agent_telemetry_init
