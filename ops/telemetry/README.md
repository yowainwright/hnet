# Telemetry

Each Mac sends OpenTelemetry data to a loopback collector. The collector applies
the default-deny policy in the [root README](../../README.md#what-stays-private), queues sanitized data,
and forwards it through private Tailscale HTTPS to the central Mac. ClickHouse
stores the signals and Grafana renders the dashboards.

```text
Codex / Gemini / Hermes / dotfiles / zsh
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

Configure supported agent vendors separately to emit OTLP to the loopback
collector with the `Authorization: Bearer` value from
`AGENT_TELEMETRY_INGEST_TOKEN`.

## Kubernetes central deployment

The central telemetry stack also has a Helm chart. Create the Kubernetes Secret
named by `secret.existingName` in `values.yaml`, then validate and install it:

```bash
./ops/apps/hnetctl/hnetctl cluster-lint
./ops/apps/hnetctl/hnetctl cluster-install
```

The chart keeps ClickHouse, Grafana, and the OTLP gateway private as
`ClusterIP` services. Tailscale ingress can be added when the cluster access
path is ready; edge Macs continue using the Compose collector.

## Zsh client

Source the client after setting an optional safe project label:

```zsh
export AGENT_TELEMETRY_PROJECT=example-project
source /path/to/hnet/ops/clients/zsh/agent-telemetry.zsh
```

The client records only command category, duration, exit code, safe project
label, host, and collector timestamp. It never records command text, arguments,
environment variables, output, or working directories.

## Dotfiles setup

The dotfiles bootstrap writes setup events to:

```text
${AGENT_TELEMETRY_STATE_DIR:-$HOME/.local/state/agent-telemetry}/dotfiles.jsonl
```

The edge collector ingests that file and keeps only event name, package name,
package manager, tool name, version, duration, status, success flag, host, and
collector timestamp.

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
