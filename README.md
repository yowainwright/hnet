# hnet

Private home-network infrastructure and observability.

## Ownership

- `hnet` owns collectors, storage, dashboards, deployment, privacy policy, and
  backup operations.
- `agent-sync` configures supported agent vendors to emit OTLP locally.
- `dotfiles` may install or source host-specific clients such as the Zsh client.

No repository contains resolved credentials, private hostnames, IP addresses,
tailnet names, telemetry payloads, or machine-specific environment files.

## Layout

| Path | Purpose |
| --- | --- |
| `ops/apps/hnetctl/` | Central and edge deployment commands |
| `ops/clients/zsh/` | Privacy-limited shell telemetry client |
| `ops/docs/` | Project and operational documentation |
| `ops/telemetry/collector/` | Edge and central OpenTelemetry Collector pipelines |
| `ops/telemetry/clickhouse/` | Storage users, backups, and dashboard views |
| `ops/telemetry/grafana/` | Provisioned data source and dashboards |

See [ops/telemetry/README.md](./ops/telemetry/README.md) for deployment and operations.

## Safety

- Keep `.env` files, backups, queues, and generated telemetry out of Git.
- Store credentials in 1Password and use references in local environment files.
- Bind services to loopback and expose them only through private Tailscale Serve.
- Preserve the default-deny contract in
  [ops/telemetry/REDACTION.md](./ops/telemetry/REDACTION.md).

## Validation

```bash
shellcheck \
  ops/apps/hnetctl/hnetctl \
  ops/telemetry/*.sh \
  ops/telemetry/clickhouse/*.sh

zsh -n ops/clients/zsh/*.zsh

docker compose \
  --env-file ops/telemetry/.env.mac-studio.example \
  -f ops/telemetry/compose.mac-studio.yml \
  config --quiet

docker compose \
  --env-file ops/telemetry/.env.edge.example \
  -f ops/telemetry/compose.edge.yml \
  config --quiet
```
