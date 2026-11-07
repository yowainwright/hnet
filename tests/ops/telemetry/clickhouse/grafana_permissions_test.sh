#!/usr/bin/env bash

set -euo pipefail

container=
users_file=${1:-ops/telemetry/clickhouse/users.xml}

main() {
  validate_local_docker
  start_isolated_database
  trap cleanup EXIT
  wait_for_database
  seed_database
  verify_reader_permissions
  echo "Grafana timeout and read-only permission tests passed."
}

validate_local_docker() {
  local endpoint
  [[ ${DOCKER_HOST:-unix://local} == unix://* ]] || fail "Tests require local Docker."
  endpoint=$(docker context inspect --format '{{.Endpoints.docker.Host}}')
  [[ $endpoint == unix://* ]] || fail "Tests require a local Docker context."
}

start_isolated_database() {
  local image parent
  parent=$(cd -- "${users_file%/*}" && pwd)
  users_file="$parent/${users_file##*/}"
  image=$(awk '$1 == "clickhouse:" { print $2 }' ops/telemetry/values.yaml)
  [[ -r $users_file && -n $image ]] || fail "Missing ClickHouse test configuration."
  container=$(docker run --detach --rm --network none --hostname localhost \
    --tmpfs /var/lib/clickhouse --tmpfs /var/log/clickhouse-server \
    --env CLICKHOUSE_SKIP_USER_SETUP=1 --env GRAFANA_CLICKHOUSE_PASSWORD=hnet-fixture \
    --volume "$users_file:/etc/clickhouse-server/users.d/hnet-grafana.xml:ro" "$image")
}

cleanup() {
  [[ -z $container ]] || docker stop --time 1 "$container" >/dev/null 2>&1 || true
}

wait_for_database() {
  local attempt
  for ((attempt = 0; attempt < 60; attempt++)); do
    docker exec "$container" clickhouse-client --query 'SELECT 1' >/dev/null 2>&1 && return
    sleep 0.25
  done
  fail "Isolated ClickHouse did not become ready."
}

seed_database() {
  docker exec "$container" clickhouse-client --multiquery --query '
    CREATE DATABASE otel;
    CREATE TABLE otel.grafana_probe (value UInt8) ENGINE=Memory;
    INSERT INTO otel.grafana_probe VALUES (1);
    CREATE DATABASE outside_telemetry;
    CREATE TABLE outside_telemetry.probe (value UInt8) ENGINE=Memory;
  ' >/dev/null
}

verify_reader_permissions() {
  local timeout driver_timeout
  timeout=$(awk '$1 == "queryTimeout:" {print $2}' ops/telemetry/grafana/provisioning/datasources/clickhouse.yaml)
  [[ $timeout =~ ^[1-9][0-9]*$ ]] || fail "Grafana needs an explicit positive query timeout."
  [[ $(reader_query 'SELECT value FROM otel.grafana_probe' --max_execution_time="$timeout") == 1 ]] ||
    fail "Grafana query timeout was rejected."
  driver_timeout=$((timeout + 5))
  [[ $(reader_query 'SELECT 1' --max_execution_time="$driver_timeout") == 1 ]] ||
    fail "Grafana driver timeout margin was rejected."
  [[ $(reader_query "SELECT getSetting('readonly')") == 1 ]] || fail "Grafana reader is not read-only."
  assert_reader_denied "SELECT 1 SETTINGS max_execution_time=61"
  assert_reader_denied "SELECT 1 SETTINGS max_execution_time=0"
  assert_reader_denied "SELECT 1 SETTINGS readonly=0"
  assert_reader_denied "SELECT 1 SETTINGS max_block_size=1"
  assert_reader_denied "INSERT INTO otel.grafana_probe VALUES (2)"
  assert_reader_denied "DROP TABLE otel.grafana_probe"
  assert_reader_denied "SELECT * FROM outside_telemetry.probe"
}

assert_reader_denied() {
  reader_query "${1:?}" >/dev/null 2>&1 || return 0
  fail "Grafana reader accepted a forbidden operation."
}

reader_query() {
  docker exec "$container" sh -c '
    query=${1:?}
    shift
    exec clickhouse-client --user grafana_reader --password "$GRAFANA_CLICKHOUSE_PASSWORD" --query "$query" "$@"
  ' hnet-fixture "$@"
}

fail() {
  echo "$1" >&2
  exit 1
}

main
