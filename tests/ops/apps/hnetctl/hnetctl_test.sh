#!/usr/bin/env bash

set -euo pipefail

script_path=${BASH_SOURCE[0]}
script_parent=${script_path%/*}
script_dir=$(cd -- "$script_parent" && pwd)
# shellcheck source=tests/ops/test_support.sh
source "$script_dir/../../test_support.sh"
# shellcheck source=tests/ops/constants.sh
source "$repo_dir/tests/ops/constants.sh"

hnetctl_source=$(sed '/^case "${1:-}"/,$d' "$repo_dir/ops/apps/hnetctl/hnetctl")

write_studio_env() {
  local studio_env=$1
  cat >"$studio_env" <<EOF
GATEWAY_PORT=$TEST_GATEWAY_PORT
GATEWAY_PORT_MAC_MINI_1=$TEST_GATEWAY_PORT_MAC_MINI_1
GATEWAY_PORT_MAC_MINI_2=$TEST_GATEWAY_PORT_MAC_MINI_2
GRAFANA_PORT=$TEST_GRAFANA_PORT
TAILSCALE_DNS_NAME=$TEST_TAILSCALE_DNS_NAME
GF_SECURITY_ADMIN_USER=$TEST_GF_SECURITY_ADMIN_USER
GF_SECURITY_ADMIN_PASSWORD=$TEST_GF_SECURITY_ADMIN_PASSWORD
CLICKHOUSE_PASSWORD=$TEST_CLICKHOUSE_PASSWORD
GRAFANA_CLICKHOUSE_PASSWORD=$TEST_GRAFANA_CLICKHOUSE_PASSWORD
AGENT_TELEMETRY_MAC_STUDIO_TOKEN=$TEST_AGENT_TELEMETRY_MAC_STUDIO_TOKEN
AGENT_TELEMETRY_MAC_MINI_1_TOKEN=$TEST_AGENT_TELEMETRY_MAC_MINI_1_TOKEN
AGENT_TELEMETRY_MAC_MINI_2_TOKEN=$TEST_AGENT_TELEMETRY_MAC_MINI_2_TOKEN
TELEMETRY_TTL=$TEST_TELEMETRY_TTL
EOF
}

write_edge_env() {
  local edge_env=$1
  cat >"$edge_env" <<EOF
AGENT_TELEMETRY_UPSTREAM=https://studio.example.ts.net:4318
AGENT_TELEMETRY_HOST=edge-test
AGENT_TELEMETRY_INGEST_TOKEN=$TEST_AGENT_TELEMETRY_MAC_STUDIO_TOKEN
EOF
}

run_studio_validation() {
  env \
    GATEWAY_PORT="$TEST_GATEWAY_PORT" \
    GATEWAY_PORT_MAC_MINI_1="$TEST_GATEWAY_PORT_MAC_MINI_1" \
    GATEWAY_PORT_MAC_MINI_2="$TEST_GATEWAY_PORT_MAC_MINI_2" \
    GRAFANA_PORT="$TEST_GRAFANA_PORT" \
    TAILSCALE_DNS_NAME="$TEST_TAILSCALE_DNS_NAME" \
    GF_SECURITY_ADMIN_USER="$TEST_GF_SECURITY_ADMIN_USER" \
    TELEMETRY_TTL="$TEST_TELEMETRY_TTL" \
    GF_SECURITY_ADMIN_PASSWORD="$TEST_GF_SECURITY_ADMIN_PASSWORD" \
    CLICKHOUSE_PASSWORD="$TEST_CLICKHOUSE_PASSWORD" \
    GRAFANA_CLICKHOUSE_PASSWORD="$TEST_GRAFANA_CLICKHOUSE_PASSWORD" \
    AGENT_TELEMETRY_MAC_STUDIO_TOKEN="$TEST_AGENT_TELEMETRY_MAC_STUDIO_TOKEN" \
    AGENT_TELEMETRY_MAC_MINI_1_TOKEN="$TEST_AGENT_TELEMETRY_MAC_MINI_1_TOKEN" \
    AGENT_TELEMETRY_MAC_MINI_2_TOKEN="$TEST_AGENT_TELEMETRY_MAC_MINI_2_TOKEN" \
    bash -c "$hnetctl_source
validate_studio_public_config
validate_studio_secrets" "$repo_dir/ops/apps/hnetctl/hnetctl"
}

test_hnetctl_resolves_the_ops_telemetry_path() {
  local missing_env="$test_root/missing-studio.env"
  local output exit_code=0
  output=$(
    cd "$repo_dir/ops/telemetry"
    env TELEMETRY_STUDIO_ENV="$missing_env" \
      PATH="$test_root/bin:$PATH" \
      OPS_TEST_DOCKER_LOG="$test_root/hnetctl-docker.log" \
      "$repo_dir/ops/apps/hnetctl/hnetctl" status 2>&1
  ) || exit_code=$?

  [[ $exit_code -ne 0 ]] || fail "hnetctl status unexpectedly succeeded without configuration."
  assert_contains "$output" "$missing_env"
}

test_hnetctl_validates_edge_ingest_token() {
  local edge_env="$test_root/edge.env"
  local docker_log="$test_root/edge-docker.log"
  local valid_token=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
  local invalid_token=short
  cat >"$edge_env" <<EOF
AGENT_TELEMETRY_UPSTREAM=https://studio.example.ts.net:4318
AGENT_TELEMETRY_HOST=edge-test
AGENT_TELEMETRY_INGEST_TOKEN=$valid_token
EOF

  TELEMETRY_EDGE_ENV="$edge_env" \
    TELEMETRY_DOCKER_BIN="$test_root/bin/docker" \
    OPS_TEST_DOCKER_LOG="$docker_log" \
    "$repo_dir/ops/apps/hnetctl/hnetctl" edge-status

  sed "s/$valid_token/$invalid_token/" "$edge_env" >"$edge_env.invalid"
  if TELEMETRY_EDGE_ENV="$edge_env.invalid" \
    TELEMETRY_DOCKER_BIN="$test_root/bin/docker" \
    OPS_TEST_DOCKER_LOG="$docker_log" \
    "$repo_dir/ops/apps/hnetctl/hnetctl" edge-status >/dev/null 2>&1; then
    fail "Short edge ingest token was accepted."
  fi

}

test_hnetctl_loads_private_redaction_pattern() {
  local config="$test_root/redaction.env" script
  local pattern='\Qperson@example.invalid\E|\Q123 Example Street (Unit 3)\E'
  printf 'AGENT_TELEMETRY_REDACT_PATTERN=%s\n' "$pattern" >"$config"
  # shellcheck disable=SC2016 # Variables expand in the child Bash process.
  script=$hnetctl_source'
unset AGENT_TELEMETRY_REDACT_PATTERN
load_studio_config observe
[[ -z ${AGENT_TELEMETRY_REDACT_PATTERN+set} ]] || exit 1
load_studio_config resolve
[[ $AGENT_TELEMETRY_REDACT_PATTERN == "$EXPECTED_REDACTION_PATTERN" ]] || exit 1
unset AGENT_TELEMETRY_REDACT_PATTERN
load_edge_config
[[ $AGENT_TELEMETRY_REDACT_PATTERN == "$EXPECTED_REDACTION_PATTERN" ]]'
  env TELEMETRY_STUDIO_ENV="$config" TELEMETRY_EDGE_ENV="$config" \
    EXPECTED_REDACTION_PATTERN="$pattern" bash -c "$script" "$repo_dir/ops/apps/hnetctl/hnetctl"
}

test_hnetctl_lints_telemetry_chart() {
  local output
  output=$("$repo_dir/ops/apps/hnetctl/hnetctl" cluster-lint)
  assert_contains "$output" "1 chart(s) linted"
}

test_hnetctl_validates_redaction_patterns() {
  local pattern output script
  script=$hnetctl_source$'\nvalidate_redaction_pattern\n[[ -n $AGENT_TELEMETRY_REDACT_PATTERN ]]'
  for pattern in '' 'a^' '\Qperson@example.invalid\E' '(?i)\Q123 Example Street\E|\Qunit 3\E'; do
    env AGENT_TELEMETRY_REDACT_PATTERN="$pattern" bash -c "$script" "$repo_dir/ops/apps/hnetctl/hnetctl"
  done
  for pattern in '[synthetic-private-pattern' '\Q\E' '\Qsynthetic-private-pattern\E|' \
    $'\\Qsynthetic-private-pattern\nEXTRA=value\\E' $'\\Qsynthetic-private-pattern\rEXTRA=value\\E'; do
    if output=$(env AGENT_TELEMETRY_REDACT_PATTERN="$pattern" \
      bash -c "$script" "$repo_dir/ops/apps/hnetctl/hnetctl" 2>&1); then
      fail "Invalid personal pattern was accepted."
    fi
    [[ $output != *synthetic-private-pattern* ]] || fail "Personal pattern appeared in validation output."
  done
}

run_redaction_start() {
  local script
  # shellcheck disable=SC2016 # Variables expand in the child Bash process.
  script=$hnetctl_source'
ensure_docker() { :; }
ensure_kubernetes() { :; }
cluster_install() { :; }
studio_serve() { :; }
wait_for_grafana() { :; }
docker_command() {
  local expected=$EXPECTED_STUDIO_PATTERN
  [[ $* != *compose.edge.yml* ]] || expected=$EXPECTED_EDGE_PATTERN
  [[ $AGENT_TELEMETRY_REDACT_PATTERN == "$expected" ]] || fail "Compose personal matches changed."
}
kubectl_command() {
  local arg key value
  for arg in "$@"; do
    [[ $arg == --from-env-file=* ]] || continue
    while IFS="=" read -r key value; do
      [[ $key == AGENT_TELEMETRY_REDACT_PATTERN ]] || continue
      [[ $value == "$EXPECTED_STUDIO_PATTERN" ]] || fail "Secret personal matches changed."
      return
    done <"${arg#--from-env-file=}"
    fail "Secret personal matches missing."
  done
  [[ $* != *apply* ]] || cat >/dev/null
}
"$TEST_START_COMMAND"
"$TEST_START_COMMAND"
[[ ${AGENT_TELEMETRY_REDACT_PATTERN:-} == "$TEST_INHERITED_PATTERN" ]]'
  env TELEMETRY_STUDIO_ENV="$test_root/pattern-studio.env" TELEMETRY_EDGE_ENV="$test_root/pattern-edge.env" \
    TEST_START_COMMAND="$1" TEST_INHERITED_PATTERN="$2" AGENT_TELEMETRY_REDACT_PATTERN="$2" \
    EXPECTED_STUDIO_PATTERN="$3" EXPECTED_EDGE_PATTERN="$4" \
    bash -c "$script" "$repo_dir/ops/apps/hnetctl/hnetctl"
}

# shellcheck disable=SC2016 # Dollar signs are literal regression data.
test_hnetctl_preserves_personal_patterns_during_startup() {
  write_studio_env "$test_root/pattern-studio.env"
  write_edge_env "$test_root/pattern-edge.env"
  printf '%s\n' 'AGENT_TELEMETRY_REDACT_PATTERN=\Qedge$$tag@example.invalid\E' >>"$test_root/pattern-edge.env"
  run_redaction_start bootstrap '' 'a^' '\Qedge$$$$tag@example.invalid\E'
  printf '%s\n' 'AGENT_TELEMETRY_REDACT_PATTERN=\Qstudio$$tag@example.invalid\E' >>"$test_root/pattern-studio.env"
  run_redaction_start operator_up '' '\Qstudio$$$$tag@example.invalid\E' '\Qedge$$$$tag@example.invalid\E'
  run_redaction_start operator_up '\Qoverride$$tag@example.invalid\E' \
    '\Qoverride$$$$tag@example.invalid\E' '\Qoverride$$$$tag@example.invalid\E'
}

test_hnetctl_creates_cluster_secret_from_studio_config() {
  local studio_env="$test_root/studio.env"
  local kubectl_log="$test_root/kubectl.log"
  local kubectl_args
  write_studio_env "$studio_env"
  : >"$kubectl_log"

  env \
    PATH="$test_root/bin:$PATH" \
    TELEMETRY_STUDIO_ENV="$studio_env" \
    HNET_KUBE_RUNTIME=none \
    HNET_KUBE_NAMESPACE=telemetry-test \
    HNET_KUBE_SECRET=hnet-test-secrets \
    OPS_TEST_HELM_LOG="$test_root/secret-helm.log" \
    OPS_TEST_KUBECTL_LOG="$kubectl_log" \
    "$repo_dir/ops/apps/hnetctl/hnetctl" cluster-bootstrap

  kubectl_args=$(<"$kubectl_log")
  assert_contains "$kubectl_args" "namespace"
  assert_contains "$kubectl_args" "telemetry-test"
  assert_contains "$kubectl_args" "secret"
  assert_contains "$kubectl_args" "hnet-test-secrets"
  assert_contains "$kubectl_args" "--from-env-file="
  assert_contains "$(<"$test_root/secret-helm.log")" 'secret.existingName=hnet-test-secrets'
}

test_hnetctl_templates_custom_secret_name() {
  local rendered
  rendered=$(HNET_KUBE_SECRET=hnet-test-secrets "$repo_dir/ops/apps/hnetctl/hnetctl" cluster-template)
  assert_contains "$rendered" 'name: hnet-test-secrets'
  [[ $rendered != *'name: hnet-telemetry-secrets'* ]] || fail 'Chart ignored the custom Secret name.'
}

run_docker_observation() {
  local script
  # shellcheck disable=SC2016 # Variables expand in the child Bash process.
  script=$hnetctl_source'
start_docker_app() { touch "$OPS_TEST_START_MARKER"; exit 80; }
"$OPS_TEST_OBSERVE_COMMAND" logs collector'
  env PATH="$test_root/bin:$PATH" TELEMETRY_DOCKER_BIN="$test_root/bin/docker" \
    TELEMETRY_STUDIO_ENV="$test_root/observe-studio.env" TELEMETRY_EDGE_ENV="$test_root/observe-edge.env" \
    OPS_TEST_DOCKER_LOG="$test_root/observe-docker.log" OPS_TEST_DOCKER_INFO_EXIT_CODE="$2" \
    OPS_TEST_CURL_LOG="$test_root/observe-curl.log" OPS_TEST_TAILSCALE_LOG="$test_root/observe-tailscale.log" \
    OPS_TEST_START_MARKER="$test_root/unexpected-start" OPS_TEST_OBSERVE_COMMAND="$1" \
    bash -c "$script" "$repo_dir/ops/apps/hnetctl/hnetctl"
}

test_status_and_logs_never_start_docker() {
  local command_name result output
  write_studio_env "$test_root/observe-studio.env"
  write_edge_env "$test_root/observe-edge.env"
  for command_name in studio_status studio_logs edge_status edge_logs; do
    run_docker_observation "$command_name" 0 >/dev/null
    : >"$test_root/observe-docker.log"
    result=0
    output=$(run_docker_observation "$command_name" 1 2>&1) || result=$?
    [[ $result -eq 1 ]] || fail 'Unavailable Docker was not reported as an observation failure.'
    assert_contains "$output" 'Docker is unavailable'
    [[ $(<"$test_root/observe-docker.log") == info ]] || fail 'Observation continued after Docker failed.'
    [[ ! -e $test_root/unexpected-start ]] || fail 'Observation attempted to start Docker.'
  done
}

run_state_changing_studio_command() {
  local script
  # shellcheck disable=SC2016 # Variables expand in the child Bash process.
  script=$hnetctl_source'
docker_ready() {
  if [[ ! -f $OPS_TEST_READY_MARKER ]]; then
    touch "$OPS_TEST_READY_MARKER"
    return 1
  fi
  return 0
}
start_docker_app() {
  touch "$OPS_TEST_START_MARKER"
}
studio_compose() {
  printf "%s\n" "$*" >>"$OPS_TEST_COMPOSE_LOG"
}
load_restic_profile() { :; }
validate_restic_config() { :; }
bash() {
  [[ $1 == "$telemetry_dir/restic-backup.sh" ]] || return 1
  touch "$OPS_TEST_ARCHIVE_MARKER"
}
telemetry_dir="$OPS_TEST_STATE_ROOT"
case "$OPS_TEST_STATE_COMMAND" in
backup) studio_backup backup synthetic-backup ;;
archive) studio_archive archive synthetic-profile synthetic-archive ;;
restart) studio_restart ;;
*) exit 2 ;;
esac'
  env TELEMETRY_STUDIO_ENV="$test_root/state-studio.env" \
    OPS_TEST_STATE_COMMAND="$1" \
    OPS_TEST_READY_MARKER="$test_root/$1-ready" \
    OPS_TEST_START_MARKER="$test_root/$1-started" \
    OPS_TEST_COMPOSE_LOG="$test_root/$1-compose.log" \
    OPS_TEST_ARCHIVE_MARKER="$test_root/$1-archived" \
    OPS_TEST_STATE_ROOT="$test_root/$1-root" \
    bash -c "$script" "$repo_dir/ops/apps/hnetctl/hnetctl"
}

test_state_changing_studio_commands_start_docker() {
  local command_name compose_log
  write_studio_env "$test_root/state-studio.env"
  for command_name in backup archive restart; do
    run_state_changing_studio_command "$command_name"
    assert_file "$test_root/$command_name-started"
    compose_log=$(<"$test_root/$command_name-compose.log")
    assert_contains "$compose_log" 'config --quiet'
  done
  assert_contains "$(<"$test_root/backup-compose.log")" 'exec -T'
  assert_contains "$(<"$test_root/archive-compose.log")" 'exec -T'
  assert_contains "$(<"$test_root/restart-compose.log")" 'restart'
}

test_archive_existing_backup_does_not_start_docker() {
  local script
  write_studio_env "$test_root/existing-archive-studio.env"
  mkdir -p "$test_root/existing-archive-root/backups/synthetic-existing"
  # shellcheck disable=SC2016 # Variables expand in the child Bash process.
  script=$hnetctl_source'
telemetry_dir="$OPS_TEST_ARCHIVE_ROOT"
docker_ready() { return 1; }
start_docker_app() { touch "$OPS_TEST_START_MARKER"; }
load_restic_profile() { :; }
validate_restic_config() { :; }
bash() {
  [[ $1 == "$telemetry_dir/restic-backup.sh" ]] || return 1
  touch "$OPS_TEST_ARCHIVE_MARKER"
}
studio_archive archive synthetic-profile synthetic-existing'
  env TELEMETRY_STUDIO_ENV="$test_root/existing-archive-studio.env" \
    OPS_TEST_ARCHIVE_ROOT="$test_root/existing-archive-root" \
    OPS_TEST_ARCHIVE_MARKER="$test_root/existing-archived" \
    OPS_TEST_START_MARKER="$test_root/existing-unexpected-start" \
    bash -c "$script" "$repo_dir/ops/apps/hnetctl/hnetctl"
  assert_file "$test_root/existing-archived"
  [[ ! -e $test_root/existing-unexpected-start ]] || fail 'Archive started Docker for an existing backup.'
}

make_backup_fakes() {
  mkdir -p "$test_root/backup-bin"
  cp "$test_root/bin/docker" "$test_root/backup-bin/selected-docker"
  cat >>"$test_root/backup-bin/selected-docker" <<'TOOL'
case " $* " in
  *" exec "*) exit "${OPS_TEST_BACKUP_EXIT_CODE:-0}" ;;
esac
TOOL
  cat >"$test_root/backup-bin/docker" <<'TOOL'
#!/bin/sh
exit 74
TOOL
  chmod +x "$test_root/backup-bin/docker"
  write_studio_env "$test_root/backup-studio.env"
}

run_backup_command() {
  env PATH="$test_root/backup-bin:$PATH" \
    TELEMETRY_STUDIO_ENV="$test_root/backup-studio.env" \
    TELEMETRY_DOCKER_BIN="$test_root/backup-bin/selected-docker" \
    OPS_TEST_DOCKER_LOG="$test_root/backup-docker.log" "$@"
}

test_backups_use_selected_docker() {
  make_backup_fakes
  run_backup_command "$repo_dir/ops/apps/hnetctl/hnetctl" backup synthetic-backup >/dev/null
  run_backup_command "$repo_dir/ops/telemetry/backup.sh" synthetic-backup >/dev/null
  assert_contains "$(<"$test_root/backup-docker.log")" "BACKUP DATABASE otel TO Disk('telemetry_backups', 'synthetic-backup')"
  : >"$test_root/backup-docker.log"
  if run_backup_command "$repo_dir/ops/apps/hnetctl/hnetctl" backup '../invalid' >/dev/null 2>&1; then
    fail 'Invalid backup name was accepted.'
  fi
  [[ $(<"$test_root/backup-docker.log") != *BACKUP_QUERY* ]] || fail 'Invalid backup reached ClickHouse.'
}

run_test_archive() {
  local script
  # shellcheck disable=SC2016 # Variables expand in the child Bash process.
  script=$hnetctl_source'
telemetry_dir="$OPS_TEST_ARCHIVE_ROOT"
load_restic_profile() { :; }
validate_restic_config() { :; }
bash() {
  [[ $1 == "$telemetry_dir/restic-backup.sh" ]] || return 1
  touch "$OPS_TEST_ARCHIVE_MARKER"
}
studio_archive archive synthetic-profile synthetic-archive'
  OPS_TEST_ARCHIVE_ROOT="$test_root/archive" OPS_TEST_ARCHIVE_MARKER="$1" run_backup_command \
    bash -c "$script" "$repo_dir/ops/apps/hnetctl/hnetctl" >/dev/null
}

test_archives_use_selected_docker() {
  run_test_archive "$test_root/archived"
  assert_file "$test_root/archived"
  assert_contains "$(<"$test_root/backup-docker.log")" "BACKUP DATABASE otel TO Disk('telemetry_backups', 'synthetic-archive')"
}

test_failed_backups_stop_archiving() {
  local result=0
  OPS_TEST_BACKUP_EXIT_CODE=75 run_test_archive "$test_root/invalid-archive" || result=$?
  [[ $result -eq 75 ]] || fail 'Archive did not propagate the backup failure.'
  [[ ! -e $test_root/invalid-archive ]] || fail 'A failed backup was archived.'
}

test_hnetctl_opens_k9s_with_orbstack_context() {
  local home_dir="$test_root/home"
  local kubectl_log="$test_root/k9s-kubectl.log"
  local orbctl_log="$test_root/orbctl.log"
  local k9s_log="$test_root/k9s.log"
  local k9s_args
  mkdir -p "$home_dir/.orbstack/k8s"
  : >"$home_dir/.orbstack/k8s/config.yml"
  : >"$kubectl_log"
  : >"$orbctl_log"
  : >"$k9s_log"

  env \
    HOME="$home_dir" \
    PATH="$test_root/bin:$PATH" \
    OPS_TEST_KUBECTL_LOG="$kubectl_log" \
    OPS_TEST_ORBCTL_LOG="$orbctl_log" \
    OPS_TEST_K9S_LOG="$k9s_log" \
    "$repo_dir/ops/apps/hnetctl/hnetctl" k9s svc

  k9s_args=$(<"$k9s_log")
  assert_contains "$k9s_args" "--kubeconfig"
  assert_contains "$k9s_args" "$home_dir/.orbstack/k8s/config.yml"
  assert_contains "$k9s_args" "--context"
  assert_contains "$k9s_args" "orbstack"
  assert_contains "$k9s_args" "--namespace"
  assert_contains "$k9s_args" "telemetry"
  assert_contains "$k9s_args" "--command"
  assert_contains "$k9s_args" "svc"
}

test_hnetctl_mprocs_bootstraps_compose_and_kubernetes() {
  local home_dir="$test_root/mprocs-home"
  local studio_env="$test_root/mprocs-studio.env"
  local edge_env="$test_root/mprocs-edge.env"
  local docker_log="$test_root/mprocs-docker.log"
  local helm_log="$test_root/mprocs-helm.log"
  local kubectl_log="$test_root/mprocs-kubectl.log"
  local orbctl_log="$test_root/mprocs-orbctl.log"
  local curl_log="$test_root/mprocs-curl.log"
  local tailscale_log="$test_root/mprocs-tailscale.log"
  local mprocs_log="$test_root/mprocs.log"
  local helm_args mprocs_args orbctl_args
  mkdir -p "$home_dir/.orbstack/k8s"
  : >"$home_dir/.orbstack/k8s/config.yml"
  write_studio_env "$studio_env"
  write_edge_env "$edge_env"
  : >"$docker_log"
  : >"$helm_log"
  : >"$kubectl_log"
  : >"$orbctl_log"
  : >"$curl_log"
  : >"$tailscale_log"
  : >"$mprocs_log"

  env \
    HOME="$home_dir" \
    PATH="$test_root/bin:$PATH" \
    TELEMETRY_STUDIO_ENV="$studio_env" \
    TELEMETRY_EDGE_ENV="$edge_env" \
    HNET_MPROCS_LOG_DIR="$test_root/mprocs-logs" \
    OPS_TEST_DOCKER_LOG="$docker_log" \
    OPS_TEST_HELM_LOG="$helm_log" \
    OPS_TEST_KUBECTL_LOG="$kubectl_log" \
    OPS_TEST_ORBCTL_LOG="$orbctl_log" \
    OPS_TEST_CURL_LOG="$curl_log" \
    OPS_TEST_TAILSCALE_LOG="$tailscale_log" \
    OPS_TEST_MPROCS_LOG="$mprocs_log" \
    "$repo_dir/ops/apps/hnetctl/hnetctl" mprocs

  orbctl_args=$(<"$orbctl_log")
  helm_args=$(<"$helm_log")
  mprocs_args=$(<"$mprocs_log")
  assert_contains "$orbctl_args" "k8s"
  assert_contains "$helm_args" "upgrade"
  assert_contains "$helm_args" "--install"
  assert_contains "$mprocs_args" "--config"
  assert_contains "$mprocs_args" "$repo_dir/ops/mprocs/hnet.yaml"
  assert_contains "$mprocs_args" "--proc-list-title"
  assert_contains "$mprocs_args" "hnet"
}

test_hnetctl_validates_gateway_tokens() {
  run_studio_validation
}

run_cluster_status() {
  env PATH="$test_root/bin:$PATH" \
    HNET_KUBE_RUNTIME=orbstack \
    HNET_KUBECONFIG="$test_root/status-kubeconfig" \
    HNET_KUBE_CONTEXT=status-test \
    HNET_KUBE_NAMESPACE=telemetry-test \
    OPS_TEST_KUBECTL_LOG="$test_root/status-kubectl.log" \
    OPS_TEST_ORBCTL_LOG="$test_root/status-orbctl.log" \
    OPS_TEST_KUBECTL_EXIT_CODE="$1" \
    "$repo_dir/ops/apps/hnetctl/hnetctl" cluster-status
}

test_cluster_status_never_starts_kubernetes() {
  local kubectl_args result=0
  run_cluster_status 0
  kubectl_args=$(<"$test_root/status-kubectl.log")
  assert_contains "$kubectl_args" "$test_root/status-kubeconfig"
  assert_contains "$kubectl_args" 'status-test'
  assert_contains "$kubectl_args" 'telemetry-test'
  assert_contains "$kubectl_args" '--request-timeout=5s'
  assert_contains "$kubectl_args" 'statefulsets,deployments,pods,services,persistentvolumeclaims'
  : >"$test_root/status-kubectl.log"
  run_cluster_status 1 >/dev/null 2>&1 || result=$?
  [[ $result -ne 0 ]] || fail "Unavailable Kubernetes reported success."
  [[ ! -e $test_root/status-orbctl.log ]] || fail "Status invoked OrbStack."
  if grep -Fq 'statefulsets' "$test_root/status-kubectl.log"; then
    fail "Status queried workloads after readiness failed."
  fi
}

test_hnetctl_rejects_duplicate_gateway_tokens() {
  if env \
    GATEWAY_PORT="$TEST_GATEWAY_PORT" \
    GATEWAY_PORT_MAC_MINI_1="$TEST_GATEWAY_PORT_MAC_MINI_1" \
    GATEWAY_PORT_MAC_MINI_2="$TEST_GATEWAY_PORT_MAC_MINI_2" \
    GRAFANA_PORT="$TEST_GRAFANA_PORT" \
    TAILSCALE_DNS_NAME="$TEST_TAILSCALE_DNS_NAME" \
    GF_SECURITY_ADMIN_USER="$TEST_GF_SECURITY_ADMIN_USER" \
    TELEMETRY_TTL="$TEST_TELEMETRY_TTL" \
    GF_SECURITY_ADMIN_PASSWORD="$TEST_GF_SECURITY_ADMIN_PASSWORD" \
    CLICKHOUSE_PASSWORD="$TEST_CLICKHOUSE_PASSWORD" \
    GRAFANA_CLICKHOUSE_PASSWORD="$TEST_GRAFANA_CLICKHOUSE_PASSWORD" \
    AGENT_TELEMETRY_MAC_STUDIO_TOKEN="$TEST_AGENT_TELEMETRY_MAC_STUDIO_TOKEN" \
    AGENT_TELEMETRY_MAC_MINI_1_TOKEN="$TEST_AGENT_TELEMETRY_MAC_STUDIO_TOKEN" \
    AGENT_TELEMETRY_MAC_MINI_2_TOKEN="$TEST_AGENT_TELEMETRY_MAC_MINI_2_TOKEN" \
    bash -c "$hnetctl_source
validate_studio_secrets" "$repo_dir/ops/apps/hnetctl/hnetctl"; then
    fail "Duplicate gateway tokens were accepted."
  fi
}

test_dashboard_refresh_reuses_the_schema_container() {
  local script output
  # shellcheck disable=SC2016 # Variables expand in the child Bash process.
  script=$hnetctl_source'
studio_observe_preflight() { :; }
studio_compose() {
  [[ $* == "ps --all --quiet dashboard-schema" ]] || exit 1
  printf "0123456789abcdef"
}
docker_command() { printf "%s" "$*"; }
studio_dashboard_refresh'
  output=$(bash -c "$script" "$repo_dir/ops/apps/hnetctl/hnetctl")
  [[ $output == 'start --attach 0123456789abcdef' ]] || fail "Refresh must reuse only the existing schema container."
}

make_fake_tools
test_dashboard_refresh_reuses_the_schema_container
test_hnetctl_resolves_the_ops_telemetry_path
test_hnetctl_validates_edge_ingest_token
test_hnetctl_loads_private_redaction_pattern
test_hnetctl_validates_redaction_patterns
test_hnetctl_preserves_personal_patterns_during_startup
test_hnetctl_lints_telemetry_chart
test_hnetctl_creates_cluster_secret_from_studio_config
test_hnetctl_templates_custom_secret_name
test_status_and_logs_never_start_docker
test_state_changing_studio_commands_start_docker
test_archive_existing_backup_does_not_start_docker
test_backups_use_selected_docker
test_archives_use_selected_docker
test_failed_backups_stop_archiving
test_hnetctl_opens_k9s_with_orbstack_context
test_hnetctl_mprocs_bootstraps_compose_and_kubernetes
test_cluster_status_never_starts_kubernetes
test_hnetctl_validates_gateway_tokens
test_hnetctl_rejects_duplicate_gateway_tokens

echo "hnetctl tests passed."
