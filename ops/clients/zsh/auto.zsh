_hnet_telemetry_auto() {
  setopt localoptions noxtrace
  [[ -o interactive ]] || return 0
  [[ -z "${_AGENT_TELEMETRY_LOADED:-}" ]] || return 0

  local token
  local security_bin="${HNET_SECURITY_BIN:-/usr/bin/security}"
  local keychain="${HNET_SHELL_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
  [[ -x "$security_bin" ]] || return 0
  token=$("$security_bin" find-generic-password -a local -s hnet.zsh.ingest \
    -w "$keychain" 2>/dev/null) || return 0
  [[ "$token" =~ '^[A-Za-z0-9._~-]{32,}$' ]] || return 0

  printf -v AGENT_TELEMETRY_INGEST_TOKEN '%s' "$token"
  export AGENT_TELEMETRY_INGEST_TOKEN
  source "${${(%):-%x}:A:h}/agent-telemetry.zsh"
}

_hnet_telemetry_auto
unfunction _hnet_telemetry_auto
source "${${(%):-%x}:A:h}/hnetctl.zsh"
source "${${(%):-%x}:A:h}/codex.zsh"
source "${${(%):-%x}:A:h}/claude.zsh"
