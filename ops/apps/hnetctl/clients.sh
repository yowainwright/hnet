#!/usr/bin/env bash

set -euo pipefail

resolve_client_tokens() {
  local key reference token seen='|'
  while IFS=$'\t' read -r key reference; do
    if [[ $reference == env:* ]]; then
      reference=$(studio_setting_value "${reference#env:}")
    fi
    token=$(resolved_config_value "$key" "$reference")
    validate_token 'Client ingestion token' "$token"
    [[ $seen != *"|$token|"* ]] || fail "Gateway tokens must be distinct."
    seen+="$token|"
    printf -v "$key" '%s' "$token"
    export "${key?}"
  done < <(jq -r '.[] | [.tokenEnv, .tokenRef] | @tsv' <<<"$clients_json")
}

client_compose_overlay() {
  jq '
    {services: {collector: {
      environment: ((map({key: .tokenEnv, value: null}) | from_entries) + {HNET_CLIENTS_CONFIG: null}),
      ports: map("127.0.0.1:\(.hostPort):\(.port)")
    }}}
  ' <<<"$clients_json"
}

serve_client_gateways() {
  local port host_port
  while IFS=$'\t' read -r port host_port; do
    tailscale_command serve --yes --bg "--https=$port" "http://127.0.0.1:$host_port"
  done < <(jq -r '.[] | [.port, .hostPort] | @tsv' <<<"$clients_json")
}

client_add() (
  set +x
  umask 077
  local name=${1:-} lock
  [[ $name =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$ ]] || fail "Usage: hnetctl client-add NAME [--yes]"
  [[ $# == 1 || ($# == 2 && ${2:-} == --yes) ]] || fail "Usage: hnetctl client-add NAME [--yes]"
  confirm_client_registration "$@"
  require_command op
  load_studio_config public
  lock="$clients_file.lock"
  mkdir "$lock" 2>/dev/null || fail "Another client registration is in progress; retry after it finishes."
  trap 'rmdir "$lock"' EXIT
  apply_client_registration "$name"
)

confirm_client_registration() {
  local name=${1:?} answer
  [[ ${2:-} != --yes ]] || return 0
  read -r -p "Register $name, refresh the collector, and configure private HTTPS access? [y/N] " answer
  [[ $answer == y || $answer == yes ]] || fail "Setup cancelled."
}

apply_client_registration() {
  local name=${1:?}
  load_client_inventory
  require_client_references
  register_named_client "$name"
  write_client_inventory
  write_client_enrollment "$name"
  studio_start
  wait_for_registered_client "$name"
  studio_serve
  echo "Client $name registered. Transfer enrollments/$name.env from the private telemetry directory to that Mac."
}

load_client_inventory() {
  require_command jq
  clients_file=${HNET_CLIENTS_FILE:-"$telemetry_dir/clients.json"}
  [[ $clients_file == /* ]] || clients_file="$telemetry_dir/$clients_file"
  if client_inventory_exists; then
    [[ -f $clients_file && ! -L $clients_file ]] || fail "Client inventory must be a regular file."
    clients_json=$(jq -ce . "$clients_file" 2>/dev/null) || fail "Client inventory is not valid JSON."
    jq -e 'all(.[]; .tokenRef | startswith("op://"))' <<<"$clients_json" >/dev/null 2>&1 ||
      fail "Client inventory must contain 1Password references."
  else
    clients_json=$(legacy_client_inventory)
  fi
  validate_client_inventory
  clients_json=$(jq -c 'map(. + {tokenEnv: ("HNET_CLIENT_TOKEN_" + (.port | tostring))})' <<<"$clients_json")
  HNET_CLIENTS_CONFIG=$(jq -c -f "${telemetry_resources:?}/collector/clients.jq" <<<"$clients_json")
  export HNET_CLIENTS_CONFIG
}

legacy_client_inventory() {
  local central_role=true
  {
    legacy_client mac-studio 4318 GATEWAY_PORT AGENT_TELEMETRY_MAC_STUDIO_TOKEN "$central_role"
    legacy_client mac-mini-1 4319 GATEWAY_PORT_MAC_MINI_1 AGENT_TELEMETRY_MAC_MINI_1_TOKEN
    legacy_client mac-mini-2 4320 GATEWAY_PORT_MAC_MINI_2 AGENT_TELEMETRY_MAC_MINI_2_TOKEN
    legacy_client macbook 4321 GATEWAY_PORT_MACBOOK AGENT_TELEMETRY_MACBOOK_TOKEN
  } | jq -s .
}

legacy_client() {
  local name=${1:?} port=${2:?} published_key=${3:?} credential_key=${4:?} central=${5:-false}
  local reference published
  reference=$(studio_setting_value "$credential_key")
  [[ -n $reference ]] || return 0
  [[ $reference == op://* ]] || reference="env:$credential_key"
  published=$(studio_setting_value "$published_key")
  published=${published:-$((port + 10000))}
  jq -n --arg name "$name" --arg ref "$reference" --argjson port "$port" \
    --argjson hostPort "$published" --argjson central "$central" \
    '{name: $name, port: $port, hostPort: $hostPort, tokenRef: $ref, central: $central}'
}

client_inventory_exists() {
  [[ ! -e $clients_file ]] || return 0
  [[ -L $clients_file ]]
}

write_client_inventory() {
  local pending
  require_client_references
  pending=$(mktemp "$clients_file.pending.XXXXXX")
  jq 'map(del(.tokenEnv))' <<<"$clients_json" >"$pending"
  chmod 600 "$pending"
  mv -f "$pending" "$clients_file"
}

require_client_references() {
  jq -e 'all(.[]; .tokenRef | startswith("op://"))' <<<"$clients_json" >/dev/null ||
    fail "Move legacy literal client tokens to 1Password before registering clients."
}

register_named_client() {
  local name=${1:?} vault id port host_port reference
  jq -e --arg name "$name" 'any(.[]; .name == $name)' <<<"$clients_json" >/dev/null && return 0
  if jq -e --arg name "$name" 'any(.[]; (.name | ascii_downcase) == ($name | ascii_downcase))' <<<"$clients_json" >/dev/null; then
    fail "A client already uses this name with different capitalization."
  fi
  vault=$(jq -r '.[0].tokenRef | split("/")[2]' <<<"$clients_json")
  [[ -n $vault ]] || fail "The central inventory needs a 1Password reference before registering clients."
  IFS=$'\t' read -r port host_port < <(next_client_ports)
  [[ -n $port && -n $host_port ]] || fail "No client ports available."
  id=$(managed_client_item "$name" "$vault")
  verify_client_item "$id" "$vault"
  reference="op://$vault/$id/password"
  clients_json=$(jq -c --arg name "$name" --arg ref "$reference" --argjson port "$port" --argjson host "$host_port" \
    '. + [{name: $name, port: $port, hostPort: $host, tokenRef: $ref}]' <<<"$clients_json")
  validate_client_inventory
}

validate_client_inventory() {
  jq -e --argjson grafana "${GRAFANA_PORT:-2021}" '
    def port: type == "number" and . == floor and . >= 1024 and . <= 65535;
    type == "array" and length > 0 and
    all(.[];
      (.name | type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]{0,62}$")) and
      (.port | port and . != 13133) and
      (.hostPort | port and . != 4317 and . != 4318 and . != $grafana) and
      (.tokenRef | type == "string" and test("^(op://[^/\\r\\n]+/[^/\\r\\n]+/[^\\r\\n]+|env:[A-Z0-9_]+)$")) and
      ((.central // false) | type == "boolean")) and
    ([.[].name | ascii_downcase] | length == (unique | length)) and
    ([.[].port] | length == (unique | length)) and
    ([.[].hostPort] | length == (unique | length)) and
    ([.[].tokenRef] | length == (unique | length)) and
    ([.[] | select(.central == true)] | length <= 1)
  ' <<<"$clients_json" >/dev/null 2>&1 || fail "Invalid client inventory: check names, references, unique ports, and central designation."
}

next_client_ports() {
  jq -r --argjson grafana "$GRAFANA_PORT" '
    def available($used; $start): first(range($start; 65536) | select(. as $p | $used | index($p) | not)) // error("No client ports available");
    available(([.[].port] + [13133]); 4318) as $port |
    available(([.[].hostPort] + [4317, 4318, $grafana]); 14318) as $host |
    if $port == null or $host == null then error("No client ports available") else [$port, $host] | @tsv end
  ' <<<"$clients_json"
}

managed_client_item() {
  local vault=${2:?} title="hnet-client-${1:?}" items count id
  items=$(op item list --vault "$vault" --format=json 2>/dev/null) || fail "1Password could not list client credentials; unlock it and retry."
  items=$(jq -c --arg title "$title" 'map(select(.title == $title))' <<<"$items")
  count=$(jq length <<<"$items")
  [[ $count -le 1 ]] || fail "Duplicate client credential items require review in 1Password."
  if [[ $count == 1 ]]; then
    jq -e '.[0].tags | index("hnet-client")' <<<"$items" >/dev/null || fail "An unmanaged item already uses this client's credential title."
    id=$(jq -r '.[0].id' <<<"$items")
    verify_client_item "$id" "$vault"
    printf '%s' "$id"
    return
  fi
  op item create --category=Password --vault "$vault" --title "$title" \
    --tags=hnet-client --generate-password=letters,digits,64 --format=json 2>/dev/null |
    jq -er '.id' || fail "1Password could not create the client credential; retry after unlocking it."
}

verify_client_item() {
  local id=${1:?} vault=${2:?}
  op item get "$id" --vault "$vault" --format=json 2>/dev/null |
    jq -e '.category == "PASSWORD" and any(.fields[]; .id == "password" and (.value | test("^[A-Za-z0-9._~-]{32,}$")))' >/dev/null ||
    fail "Existing client credential is invalid; review its password field in 1Password."
}

write_client_enrollment() {
  local name=${1:?} destination="$telemetry_dir/enrollments" pending pattern
  pattern=$(studio_setting_value AGENT_TELEMETRY_REDACT_PATTERN)
  [[ ! -L $destination && ! -L $destination/$name.env ]] || fail "Enrollment destination must not be a symlink."
  install -d -m 700 "$destination"
  pending=$(mktemp "$destination/.enrollment.XXXXXX")
  jq -r --arg name "$name" --arg dns "$TAILSCALE_DNS_NAME" --arg pattern "${pattern:-a^}" '
    .[] | select(.name == $name) |
    "AGENT_TELEMETRY_HOST=\(.name)\nAGENT_TELEMETRY_UPSTREAM=https://\($dns):\(.port)\nAGENT_TELEMETRY_INGEST_TOKEN=\(.tokenRef)\nAGENT_TELEMETRY_REDACT_PATTERN=\($pattern)"
  ' <<<"$clients_json" >"$pending"
  chmod 600 "$pending"
  mv -f "$pending" "$destination/$name.env"
}

studio_setting_value() {
  local wanted=${1:?} key value
  [[ -z ${!wanted:-} ]] || {
    printf '%s' "${!wanted}"
    return
  }
  [[ -f ${studio_env:?} ]] || return 0
  while IFS='=' read -r key value; do
    [[ $key != "$wanted" ]] || {
      printf '%s' "$value"
      return
    }
  done <"$studio_env"
}

wait_for_registered_client() {
  local name=${1:?} key port attempt result
  IFS=$'\t' read -r key port < <(jq -r --arg name "$name" '.[] | select(.name == $name) | [.tokenEnv, .hostPort] | @tsv' <<<"$clients_json")
  for ((attempt = 1; attempt <= 30; attempt++)); do
    result=$(printf 'header = "Authorization: Bearer %s"\n' "${!key}" |
      curl --config - --silent --output /dev/null --write-out '%{http_code}' \
        --connect-timeout 2 --max-time 3 --header 'Content-Type: application/json' \
        --data-binary '{"resourceLogs":[]}' "http://127.0.0.1:$port/v1/logs") || result=unreachable
    [[ $result != 200 ]] || return 0
    sleep 1
  done
  fail "Registered client receiver did not become ready; rerun client-add after checking the collector."
}
