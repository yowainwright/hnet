# hnet

Private home-network infrastructure and observability.

No resolved credentials, private hostnames, IP addresses, tailnet names,
telemetry payloads, or machine-specific environment files belong in this
repository.

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
See [ops/docs/PROJECT.md](./ops/docs/PROJECT.md) for the service flow.

## Safety

- Keep `.env` files, backups, queues, and generated telemetry out of Git.
- Store credentials in 1Password and use references in local environment files.
- Bind services to loopback and expose them only through private Tailscale Serve.
- Preserve the default-deny contract in
  [ops/telemetry/REDACTION.md](./ops/telemetry/REDACTION.md).
