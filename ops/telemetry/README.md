# Telemetry

Each Mac sends OpenTelemetry data to a loopback collector. The collector applies
the default-deny policy in [REDACTION.md](./REDACTION.md), queues sanitized data,
and forwards it through private Tailscale HTTPS to the central Mac. ClickHouse
stores the signals and Grafana renders the dashboards.

```text
Codex / Gemini / Hermes / zsh
          |
          v
Mac edge collector -- Tailscale HTTPS --> central gateway
    disk queue                                  |
                                                v
                                         ClickHouse --> Grafana
                                                |
                              encrypted Restic backups
```

The central host binds Grafana and the OTLP gateway to loopback. Tailscale Serve
provides private access. Do not enable Funnel or router port forwarding.

## Central host

Install OrbStack or Docker Desktop, Tailscale, the 1Password CLI, and Restic.
Copy the example environment and replace every placeholder:

```bash
cp ops/telemetry/.env.mac-studio.example ops/telemetry/.env.mac-studio
./ops/apps/hnetctl/hnetctl bootstrap
./ops/apps/hnetctl/hnetctl status
```

The environment file may contain 1Password references. Resolved secrets are
exported only to Docker Compose and are never written back to disk.

The local ports have separate roles:

| Port | Binding | Purpose |
| --- | --- | --- |
| `2021` | loopback | Grafana behind Tailscale Serve |
| `14318` | loopback | Central OTLP gateway behind Tailscale Serve |
| `4317` / `4318` | loopback | Edge collector for local clients |

## Edge Macs

Install OrbStack or Docker Desktop and Tailscale, then configure the private
gateway and a non-sensitive host label:

```bash
cp ops/telemetry/.env.edge.example ops/telemetry/.env.edge
./ops/apps/hnetctl/hnetctl edge-start
./ops/apps/hnetctl/hnetctl edge-status
```

Run `agent-sync global` separately to configure supported agent vendors to emit
OTLP to the loopback collector.

## Zsh client

Source the client after setting an optional safe project label:

```zsh
export AGENT_TELEMETRY_PROJECT=agent-sync
source /path/to/hnet/ops/clients/zsh/agent-telemetry.zsh
```

The client records only command category, duration, exit code, safe project
label, host, and collector timestamp. It never records command text, arguments,
environment variables, output, or working directories.

## Operations

```bash
./ops/apps/hnetctl/hnetctl logs grafana
./ops/apps/hnetctl/hnetctl logs collector
./ops/apps/hnetctl/hnetctl backup
```

For encrypted NAS or cloud archives, copy the corresponding Restic example,
replace its placeholders, and initialize it:

```bash
cp ops/telemetry/.env.restic.nas.example ops/telemetry/.env.restic.nas
./ops/apps/hnetctl/hnetctl restic-init nas
./ops/apps/hnetctl/hnetctl archive nas
```

Live ClickHouse telemetry expires after 14 days. Keep backup retention separate
and test restores periodically.
