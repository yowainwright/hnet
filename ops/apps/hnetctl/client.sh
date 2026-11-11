#!/usr/bin/env bash

set -euo pipefail

client_install() {
  set +x
  umask 077
  client_initialize install
  client_parse_options "$@"
  [[ $client_help == false ]] || {
    client_usage
    return
  }
  client_prepare_install
  client_deploy
  client_enroll
}

client_prepare_install() {
  client_verify_source "$client_source"
  [[ $client_install_deps == false ]] || client_install_dependencies
  client_check_prerequisites
  client_require_ready
  client_prepare_settings
  client_validate_destination
  client_preflight_install
  client_confirm "Install the client collector, shell startup, and Codex telemetry?"
  client_resolve_settings
  client_probe "$client_upstream/v1/logs"
}

client_check() {
  set +x
  client_initialize check
  client_parse_options "$@"
  [[ $client_help == false ]] || {
    client_usage
    return
  }
  client_verify_source "$client_source"
  client_check_installed_archive "$@"
  client_check_prerequisites
  if [[ $client_prerequisites_only == false ]]; then
    client_check_enrollment
  fi
  client_require_ready
  [[ $client_connection == false ]] || client_check_connections
  echo "Client checks passed."
}

client_bundle() (
  client_initialize bundle
  [[ $# == 0 ]] || fail "Usage: hnetctl client-bundle"
  client_verify_source "$client_source"
  local bundle_dir client_stage
  bundle_dir=$(client_bundle_directory)
  mkdir -p "$bundle_dir"
  bundle_dir=$(cd -- "$bundle_dir" && pwd)
  client_stage=$(mktemp -d "$bundle_dir/.hnet-client.XXXXXX")
  trap 'rm -rf -- "$client_stage"' EXIT
  client_copy_files "$client_source" "$client_stage/hnet-client"
  client_create_checksums "$client_stage/hnet-client"
  client_archive "$client_stage" "$bundle_dir/hnet-client-macos.tar.gz"
  (cd "$bundle_dir" && shasum -a 256 hnet-client-macos.tar.gz >hnet-client-macos.tar.gz.sha256)
  echo "Created hnet-client-macos.tar.gz and its SHA-256 checksum."
)

client_bundle_directory() {
  local output="$client_source/dist"
  [[ -z ${HNET_PACKAGE_ROOT:-} ]] || output="$client_prefix/dist"
  printf '%s' "${HNET_CLIENT_BUNDLE_DIR:-$output}"
}

client_check_installed_archive() {
  [[ $client_prerequisites_only == false ]] || return 0
  [[ -z ${HNET_PACKAGE_ROOT:-} ]] || return 0
  [[ ! -e "$client_source/.git" ]] || return 0
  client_reject_symlinks "$client_prefix/.hnet-client"
  [[ -f "$client_prefix/.hnet-client" ]] || return 0
  client_require_managed_prefix
  local installed="$client_prefix/ops/apps/hnetctl/hnetctl"
  client_reject_symlinks "$installed"
  [[ ! "$client_source" -ef "$client_prefix" ]] || return 0
  [[ -x $installed ]] || fail "Use the installed package's hnetctl to check this enrollment."
  HNET_CLIENT_HOME="$client_prefix" exec "$installed" client-check "$@"
}

client_initialize() {
  client_mode=${1:?}
  client_source=$(cd -- "${ops_dir:?}/.." && pwd)
  client_prefix=${HNET_CLIENT_HOME:-"$HOME/.local/share/hnet"}
  client_config_input=
  client_install_deps=false
  client_yes=false
  client_help=false
  client_prerequisites_only=false
  client_connection=false
  client_failures=0
  client_upstream=
  client_host=
  client_token_ref=
  client_pattern=a^
}

client_parse_options() {
  while (($# > 0)); do
    case "$1" in
    --prefix | --config)
      [[ $# -ge 2 && -n $2 ]] || fail "$1 requires a value."
      client_set_option "$1" "$2"
      shift 2
      ;;
    *)
      client_parse_switch "$1"
      shift
      ;;
    esac
  done
  client_validate_options
}

client_validate_options() {
  case "$client_mode" in
  install)
    [[ $client_prerequisites_only == false ]] || fail "--prerequisites requires --check."
    [[ $client_connection == false ]] || fail "--connection requires --check."
    ;;
  check)
    [[ $client_install_deps == false ]] || fail "Omit --check when installing dependencies."
    ;;
  esac
}

client_parse_switch() {
  case "${1:?}" in
  --install-deps) client_install_deps=true ;;
  --yes) client_yes=true ;;
  --prerequisites) client_prerequisites_only=true ;;
  --connection) client_connection=true ;;
  --help) client_help=true ;;
  *) fail "Unknown client option; use --help." ;;
  esac
}

client_set_option() {
  case "${1:?}" in
  --prefix)
    [[ $client_mode == install ]] || fail "--prefix applies only to installation; run the installed hnetctl to check it."
    client_prefix=${2:?}
    ;;
  --config) client_config_input=${2:?} ;;
  esac
}

client_usage() {
  cat <<'USAGE'
Install: ./install.sh [--install-deps] [--config FILE] [--prefix DIRECTORY] [--yes]
Check:   ./install.sh --check [--prerequisites] [--connection] [--config FILE]

Default install location: ~/.local/share/hnet
--install-deps uses an existing Homebrew installation and the client Brewfile.
--yes approves client setup and optional dependency installation without prompts.
Configuration contains this Mac's label, central HTTPS address, and an op:// reference.
Ordinary checks do not install, start apps, resolve ingestion secrets, or change configuration.
--connection additionally reads the existing Keychain token and sends empty OTLP probes.
USAGE
}

client_check_prerequisites() {
  [[ $(uname -s) == Darwin ]] || client_problem "macOS is required."
  client_check_commands
  client_check_app "1Password"
  client_check_docker
  client_check_tailscale
  client_check_codex
}

client_check_commands() {
  local tool
  for tool in bash zsh curl security open pgrep plutil shasum install tar; do
    command -v "$tool" >/dev/null 2>&1 || client_problem "Missing macOS tool: $tool"
  done
  if client_op_available; then
    echo "OK: 1Password CLI."
    return
  fi
  client_problem "Install 1Password CLI: https://www.1password.dev/cli/get-started"
}

client_op_available() {
  command -v op >/dev/null 2>&1 || return 1
  op --version >/dev/null 2>&1
}

client_check_app() {
  local name=${1:?} applications=${HNET_CLIENT_APPLICATIONS_DIR:-/Applications}
  [[ -d "$applications/$name.app" ]] && return 0
  [[ -d "$HOME/Applications/$name.app" ]] && return 0
  client_problem "Install $name for Mac and complete its first-run setup."
}

client_check_docker() {
  docker_bin=$(resolve_docker_bin || true)
  [[ -n $docker_bin ]] || {
    client_problem "Install OrbStack or Docker Desktop."
    return
  }
  client_docker_is_local || {
    client_problem "Select a local Docker context; remote engines are refused."
    return
  }
  docker_ready || {
    client_problem "Open OrbStack/Docker Desktop and finish setup; enable Start at login."
    return
  }
  "$docker_bin" compose version >/dev/null 2>&1 || {
    client_problem "Docker Compose is unavailable."
    return
  }
  echo "OK: local Docker engine and Compose."
}

client_check_tailscale() {
  local state
  state=$(tailscale_command status --json 2>/dev/null | plutil -extract BackendState raw -o - - 2>/dev/null) || true
  [[ $state == Running ]] || {
    client_problem "Open Tailscale and sign into the central Mac's tailnet."
    return
  }
  echo "OK: Tailscale connected."
}

client_check_codex() {
  command -v codex >/dev/null 2>&1 || {
    client_problem "Install Codex CLI: https://learn.chatgpt.com/docs/cli"
    return
  }
  codex --version >/dev/null 2>&1 || {
    client_problem "Codex CLI cannot run; repair its installation."
    return
  }
  codex login status >/dev/null 2>&1 || {
    client_problem "Sign into Codex CLI: codex login"
    return
  }
  (codex_validate_config) >/dev/null 2>&1 || {
    client_problem "Codex rejected its configuration; repair or update Codex CLI."
    return
  }
  echo "OK: Codex CLI, login, and configuration."
}

client_require_ready() {
  [[ $client_failures == 0 ]] || fail "Client is not ready: $client_failures check(s) need attention."
}

client_install_dependencies() {
  command -v brew >/dev/null 2>&1 ||
    fail "Homebrew is missing. Install it from https://brew.sh, or install the vendor apps and rerun without --install-deps."
  client_confirm "Install missing client apps with Homebrew (OrbStack, Tailscale, 1Password, Codex CLI)?"
  brew bundle install --no-upgrade --file "${ops_dir:?}/clients/Brewfile"
  echo "Finish app setup: open OrbStack, sign into Tailscale, and unlock 1Password."
  echo "In 1Password: Settings > Developer > Integrate with 1Password CLI."
  echo "Sign into Codex with: codex login"
}

client_confirm() {
  local answer
  [[ $client_yes == false ]] || return 0
  [[ -t 0 ]] || fail "Run interactively, or use --yes to approve the displayed setup."
  read -r -p "${1:?} [y/N] " answer
  [[ $answer == y || $answer == yes ]] || fail "Setup cancelled."
}

client_prepare_settings() {
  local existing="$client_prefix/ops/telemetry/.env.edge"
  if [[ -n $client_config_input ]]; then
    [[ -f $client_config_input ]] || fail "The enrollment configuration file does not exist."
    [[ ! -f $existing ]] || cmp -s "$client_config_input" "$existing" ||
      fail "Existing enrollment differs; edit the installed private configuration explicitly."
    client_read_settings "$client_config_input"
    return
  fi
  [[ ! -f $existing ]] || {
    client_read_settings "$existing"
    return
  }
  client_prompt_settings
}

client_prompt_settings() {
  [[ -t 0 ]] || fail "Provide --config FILE for noninteractive enrollment. See README.md."
  echo "Use the name, central HTTPS URL, and token reference registered by hnetctl client-add."
  read -r -p 'Mac label: ' client_host
  read -r -s -p 'Central Tailscale HTTPS URL including assigned port (hidden): ' client_upstream
  printf '\n'
  read -r -s -p '1Password op:// token reference (hidden): ' client_token_ref
  printf '\n'
  read -r -s -p 'Additional redaction pattern/reference (hidden; Enter uses a^): ' client_pattern
  printf '\n'
  client_pattern=${client_pattern:-a^}
}

client_preflight_install() {
  local existing_config
  [[ $client_prefix == /* && $client_prefix != / ]] || fail "Install location must be an absolute directory below root."
  client_single_line "$client_prefix"
  client_reject_symlinks "$client_prefix"
  client_reject_symlinks "$client_prefix/.hnet-client"
  client_reject_symlinks "$client_prefix/ops/telemetry/.env.edge"
  client_require_managed_prefix
  existing_config=$(codex_config_file)
  [[ ! -L $existing_config ]] || fail "Codex configuration is a symlink; integrate its telemetry manually."
  client_check_existing_codex "$existing_config"
  [[ -z ${HNET_PACKAGE_ROOT:-} ]] || export HNET_SHELL_STARTUP_CLIENT="$client_prefix/ops/clients/zsh/auto.zsh"
  local ops_dir="$client_prefix/ops"
  shell_startup_preflight
  echo "Ready to install client slot $client_host; central storage and network exposure are unchanged."
}

client_require_managed_prefix() {
  [[ -d $client_prefix ]] || return 0
  [[ -z $(find "$client_prefix" -mindepth 1 -maxdepth 1 -print -quit) ]] && return 0
  [[ -f "$client_prefix/.hnet-client" ]] || {
    client_require_central_prefix
    return
  }
  [[ $(<"$client_prefix/.hnet-client") == hnet-client-v1 ]] || fail "Install location has an unknown client marker."
}

client_require_central_prefix() {
  [[ -n ${HNET_PACKAGE_ROOT:-} ]] ||
    fail "Install location already contains unmanaged files; choose another --prefix."
  local studio_env="$client_prefix/ops/telemetry/.env.mac-studio"
  local telemetry_dir="${studio_env%/*}"
  client_reject_symlinks "$studio_env"
  client_reject_symlinks "$client_prefix/ops/clients"
  [[ -f $studio_env && ! -e "$client_prefix/ops/clients" ]] ||
    fail "Central enrollment requires a regular central configuration and no existing client code."
  load_studio_config public
  validate_studio_public_config
  local port
  port=$(jq -er --arg name "$client_host" '.[] | select(.central == true and .name == $name) | .port' <<<"${clients_json:?}") ||
    fail "Only the designated central client can adopt central state."
  [[ $client_upstream == "https://$TAILSCALE_DNS_NAME:$port" ]] ||
    fail "Central enrollment must use this host's registered Tailscale endpoint."
}

client_check_existing_codex() {
  local config=${1:?}
  [[ -f $config ]] || return 0
  if grep -Fxq '# >>> hnet codex >>>' "$config"; then
    codex_require_local_config
    return
  fi
  grep -Eq '^[[:space:]]*(\[[^]]*otel|otel[.[:space:]]*=)' "$config" || return 0
  fail "Existing Codex telemetry needs a manual merge before client installation."
}

client_resolve_settings() {
  unset AGENT_TELEMETRY_INGEST_TOKEN AGENT_TELEMETRY_REDACT_PATTERN
  AGENT_TELEMETRY_UPSTREAM=$client_upstream
  AGENT_TELEMETRY_HOST=$client_host
  AGENT_TELEMETRY_INGEST_TOKEN=$(resolved_config_value AGENT_TELEMETRY_INGEST_TOKEN "$client_token_ref" 2>/dev/null) ||
    fail "1Password could not read the token. Unlock it, enable CLI integration, and check the reference."
  AGENT_TELEMETRY_REDACT_PATTERN=$(resolved_config_value AGENT_TELEMETRY_REDACT_PATTERN "$client_pattern" 2>/dev/null) ||
    fail "1Password could not read the additional redaction setting."
  export AGENT_TELEMETRY_UPSTREAM AGENT_TELEMETRY_HOST AGENT_TELEMETRY_INGEST_TOKEN AGENT_TELEMETRY_REDACT_PATTERN
  validate_edge_config
}

client_deploy() {
  if [[ -n ${HNET_PACKAGE_ROOT:-} ]]; then
    client_deploy_package
  else
    client_copy_files "$client_source" "$client_prefix"
    client_create_checksums "$client_prefix"
  fi
  printf 'hnet-client-v1\n' >"$client_prefix/.hnet-client"
  local config="$client_prefix/ops/telemetry/.env.edge"
  [[ ! -e $config ]] || return 0
  install -d -m 700 "${config%/*}"
  printf 'AGENT_TELEMETRY_UPSTREAM=%s\nAGENT_TELEMETRY_HOST=%s\nAGENT_TELEMETRY_INGEST_TOKEN=%s\nAGENT_TELEMETRY_REDACT_PATTERN=%s\n' \
    "$client_upstream" "$client_host" "$client_token_ref" "$client_pattern" >"$config"
  chmod 600 "$config"
}

client_deploy_package() {
  local startup="$client_prefix/ops/clients/zsh/auto.zsh"
  [[ -n ${HNET_PACKAGE_ENTRYPOINT:-} ]] || fail "Packaged entrypoint is missing."
  client_reject_symlinks "$startup"
  install -d -m 700 "${startup%/*}"
  {
    printf 'export HNET_CLIENT_HOME=%q\n' "$client_prefix"
    printf 'if [[ -x %q && -r %q ]]; then\n' "$HNET_PACKAGE_ENTRYPOINT" "$HNET_PACKAGE_ROOT/ops/clients/zsh/auto.zsh"
    printf '  export HNET_PACKAGE_ENTRYPOINT=%q\n' "$HNET_PACKAGE_ENTRYPOINT"
    printf '  source %q\nfi\n' "$HNET_PACKAGE_ROOT/ops/clients/zsh/auto.zsh"
  } >"$startup"
  chmod 600 "$startup"
}

client_enroll() {
  [[ -n ${HNET_PACKAGE_ROOT:-} ]] || ops_dir="$client_prefix/ops"
  telemetry_dir="$client_prefix/ops/telemetry"
  edge_env="$telemetry_dir/.env.edge"
  edge_start
  shell_enable
  codex_enable
  echo "Client installed. Enable Docker Start at login; keep Tailscale connected."
  echo "Open a new terminal: hnetctl client-check --connection"
  echo "Then use codex, codex-app, or claude and verify the first completed turn in Grafana."
}

client_verify_source() {
  local root=${1:?} relative
  [[ -f "$root/ops/clients/files.txt" ]] || fail "Client file manifest is missing."
  while IFS= read -r relative; do
    client_validate_relative "$relative"
    [[ -f "$root/$relative" ]] || fail "A required client file is missing: $relative"
    [[ ! -L "$root/$relative" ]] || fail "Client code must contain regular files, not symlinks."
  done <"$root/ops/clients/files.txt"
  if [[ -f "$root/SHA256SUMS" ]]; then
    (cd "$root" && shasum -a 256 -c SHA256SUMS >/dev/null 2>&1) || fail "Client checksum verification failed."
    return
  fi
  [[ -e "$root/.git" ]] || fail "Client checksums are missing; use a freshly built bundle."
}

client_copy_files() {
  local from=${1:?} to=${2:?} relative mode target
  [[ $from != "$to" ]] || return 0
  while IFS= read -r relative; do
    client_validate_relative "$relative"
    target="$to/$relative"
    client_reject_symlinks "$target"
    install -d -m 700 "${target%/*}"
    mode=644
    case "$relative" in *.sh | */hnetctl) mode=755 ;; esac
    install -m "$mode" "$from/$relative" "$target"
  done <"$from/ops/clients/files.txt"
}

client_archive() {
  local stage=${1:?} archive=${2:?} root=${3:-hnet-client} ownership=(--owner=0 --group=0 --numeric-owner)
  if tar --version | grep -q bsdtar; then
    ownership=(--uid 0 --gid 0 --uname root --gname root)
  fi
  COPYFILE_DISABLE=1 tar "${ownership[@]}" -czf "$archive" -C "$stage" "$root"
}

client_create_checksums() {
  local root=${1:?}
  client_reject_symlinks "$root/SHA256SUMS"
  (
    cd "$root"
    while IFS= read -r relative; do
      shasum -a 256 "$relative"
    done <ops/clients/files.txt >SHA256SUMS
  )
}

client_check_enrollment() {
  local config=${client_config_input:-${edge_env:?}}
  [[ -f $config ]] || {
    client_problem "Run ./install.sh to configure and enroll this Mac."
    return
  }
  client_read_settings "$config"
  client_validate_destination
  echo "OK: private enrollment configuration for $client_host."
  (shell_status) >/dev/null 2>&1 || client_problem "Shell enrollment is missing or points elsewhere; rerun the installer."
  (codex_require_local_config) >/dev/null 2>&1 || client_problem "Codex telemetry is missing or changed; review its marked hnet block."
  client_check_collector
}

client_check_collector() {
  local container health
  [[ -n $docker_bin ]] || return 0
  client_docker_is_local || return 0
  container=$("$docker_bin" ps --filter label=com.docker.compose.project=agent-telemetry-edge \
    --filter label=com.docker.compose.service=collector --format '{{.ID}}' 2>/dev/null) || true
  [[ $container =~ ^[0-9a-f]{12,64}$ ]] || {
    client_problem "The local edge collector is not running."
    return
  }
  health=$("$docker_bin" inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container" 2>/dev/null) || true
  [[ $health == healthy ]] || {
    client_problem "The local edge collector is not healthy yet."
    return
  }
  echo "OK: local edge collector is healthy."
}

client_check_connections() {
  [[ $client_prerequisites_only == false ]] || fail "--connection requires enrollment checks."
  agent_auth_environment
  AGENT_TELEMETRY_INGEST_TOKEN=${OTEL_EXPORTER_OTLP_HEADERS#Authorization=Bearer }
  client_probe http://127.0.0.1:4318/v1/logs
  client_probe "$client_upstream/v1/logs"
  echo "OK: local and central collectors accept authenticated empty OTLP requests."
  echo "A completed Codex turn visible in Grafana proves usage delivery."
}

client_docker_is_local() {
  local endpoint
  [[ ${DOCKER_HOST:-unix://local} == unix://* ]] || return 1
  endpoint=$("${docker_bin:?}" context inspect --format '{{.Endpoints.docker.Host}}' 2>/dev/null) || return 1
  [[ $endpoint == unix://* ]]
}

client_problem() {
  echo "ACTION: ${1:?}" >&2
  client_failures=$((client_failures + 1))
}

client_probe() {
  local result
  result=$(printf 'header = "Authorization: Bearer %s"\n' "$AGENT_TELEMETRY_INGEST_TOKEN" |
    curl --config - --silent --output /dev/null --write-out '%{http_code}' --connect-timeout 5 --max-time 10 \
      --header 'Content-Type: application/json' --data-binary '{"resourceLogs":[]}' "${1:?}" 2>/dev/null) ||
    fail "Collector is unreachable. Check Tailscale, the central Mac, and the assigned port."
  [[ $result == 200 ]] || fail "Collector rejected the connection (HTTP $result); verify the assigned token and port."
}

client_validate_relative() {
  local relative=${1:?}
  [[ $relative != /* ]] || fail "Client manifest contains an absolute path."
  [[ $relative != *..* ]] || fail "Client manifest contains path traversal."
  case "$relative" in
  install.sh | LICENSE | VERSION | README.md | ops/apps/hnetctl/*.sh | ops/apps/hnetctl/hnetctl | ops/clients/* | ops/telemetry/compose.edge.yml | ops/telemetry/collector/edge.yaml | ops/telemetry/.env.edge.example) ;;
  *) fail "Client manifest includes a file outside the client surface." ;;
  esac
  case "$relative" in
  *$'\n'* | *$'\r'* | *' '*) fail "Client manifest contains unsupported characters." ;;
  esac
}

client_reject_symlinks() {
  local target=${1:?}
  while :; do
    case "$target" in / | . | '') return 0 ;; esac
    [[ ! -L $target ]] || fail "Client installation cannot traverse symlinks."
    [[ $target == */* ]] || return 0
    target=${target%/*}
    [[ -n $target ]] || return 0
  done
}

client_read_settings() {
  local key value seen='|'
  while client_read_setting_line; do
    case "$key" in
    '' | '#'*) continue ;;
    AGENT_TELEMETRY_UPSTREAM | AGENT_TELEMETRY_HOST | AGENT_TELEMETRY_INGEST_TOKEN | AGENT_TELEMETRY_REDACT_PATTERN) ;;
    *) fail "Unsupported enrollment configuration key." ;;
    esac
    [[ $seen != *"|$key|"* ]] || fail "Duplicate enrollment configuration key."
    seen+="$key|"
    client_assign_setting "$key" "$value"
  done <"${1:?}"
}

client_read_setting_line() {
  IFS='=' read -r key value || [[ -n $key ]]
}

client_assign_setting() {
  case "${1:?}" in
  AGENT_TELEMETRY_UPSTREAM) client_upstream=${2:-} ;;
  AGENT_TELEMETRY_HOST) client_host=${2:-} ;;
  AGENT_TELEMETRY_INGEST_TOKEN) client_token_ref=${2:-} ;;
  AGENT_TELEMETRY_REDACT_PATTERN) client_pattern=${2:-a^} ;;
  esac
}

client_validate_destination() {
  AGENT_TELEMETRY_UPSTREAM=$client_upstream
  AGENT_TELEMETRY_HOST=$client_host
  validate_edge_destination
  [[ $client_token_ref == op://*/*/* ]] || fail "Use a 1Password op:// reference, not a resolved token."
  client_single_line "$client_token_ref"
  client_single_line "$client_pattern"
}

client_single_line() {
  local value=${1:-}
  [[ $value != *$'\n'* ]] || fail "Enrollment values must be single-line."
  [[ $value != *$'\r'* ]] || fail "Enrollment values must be single-line."
}
