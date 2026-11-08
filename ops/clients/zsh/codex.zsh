_hnet_codex_startup() {
  local config="${HNET_CODEX_CONFIG:-${CODEX_HOME:-$HOME/.codex}/config.toml}"
  [[ -f "$config" ]] || return 0
  grep -Fxq '# >>> hnet codex >>>' "$config" || return 0

  codex() {
    command "${HNET_PACKAGE_ENTRYPOINT:-${${(%):-%x}:A:h}/../../apps/hnetctl/hnetctl}" codex "$@"
  }

  codex-app() {
    command "${HNET_PACKAGE_ENTRYPOINT:-${${(%):-%x}:A:h}/../../apps/hnetctl/hnetctl}" codex-app "$@"
  }

  chatgpt-app() {
    command "${HNET_PACKAGE_ENTRYPOINT:-${${(%):-%x}:A:h}/../../apps/hnetctl/hnetctl}" chatgpt-app "$@"
  }
}

_hnet_codex_startup
unfunction _hnet_codex_startup
