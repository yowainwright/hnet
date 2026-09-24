# Telemetry

Each Mac sends OpenTelemetry data to a loopback collector. The collector applies
the filtering and masking in the [root README](../../README.md#what-stays-private), queues the results,
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

The environment file may contain 1Password references. Resolved values are not
written back to that file. Kubernetes setup also copies them into its Secret.

## Personal matches

<!-- personal masking configuration from collector/edge.yaml, collector/gateway.yaml, and ../apps/hnetctl/hnetctl -->

Set `AGENT_TELEMETRY_REDACT_PATTERN` in each private edge/central environment
file, or use a 1Password field reference. It adds your known emails, addresses,
or other sensitive values to attribute masking. The default `a^` matches nothing.
These invented values are matched literally with `\Q...\E` and separated with `|`:

```dotenv
AGENT_TELEMETRY_REDACT_PATTERN=\Qperson@example.invalid\E|\Q123 Example Street\E
```

Use the same pattern on every collector. Matching is case-sensitive unless the
pattern starts with `(?i)`. `hnetctl` accepts only nonempty `\Qliteral\E` entries
separated by `|`, on one line; arbitrary regex syntax and `\E` inside an entry
are rejected without printing the value. Empty settings become `a^`.
Put actual personal details only in ignored environment files or 1Password.
Enter dollar signs literally; `hnetctl` escapes them for the collector.

After approval, `start`/`edge-start` recreate changed Compose containers with the
resolved pattern; `restart` alone does not refresh their environment.
`cluster-secrets` supplies the pattern to the Kubernetes Secret; the collector
pod must also be replaced to refresh its environment. When managing that Secret
directly, double each `$` in the literal pattern to escape collector expansion
(for example, `person$$tag` for `person$tag`). Omit the optional key or set `a^`
to disable personal matching. Do not print resolved collector configuration or
enable debug payload logging. Coverage and limitations are in the root privacy
section.

## Gateway tokens

Create one 1Password item named `agent-telemetry` with the three gateway token
fields: `mac-studio-token`, `mac-mini-1-token`, and `mac-mini-2-token`.

The local ports have separate roles:

| Port | Binding | Purpose |
| --- | --- | --- |
| `2021` | loopback | Grafana behind Tailscale Serve |
| `14318` | loopback | `mac-studio` gateway behind Tailscale Serve |
| `14319` | loopback | `mac-mini-1` gateway behind Tailscale Serve |
| `14320` | loopback | `mac-mini-2` gateway behind Tailscale Serve |
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

The gateway has one authenticated slot per Mac: `mac-studio` uses port `4318`,
`mac-mini-1` uses `4319`, and `mac-mini-2` uses `4320`. Copy the edge example
for each Mac and update its host, upstream port, and token field.

## Kubernetes central deployment

The central telemetry stack also has a Helm chart. Create the Kubernetes Secret
named by `secret.existingName` in `values.yaml` with the database and Grafana
credentials, then validate and install it:

```bash
./ops/apps/hnetctl/hnetctl cluster-lint
./ops/apps/hnetctl/hnetctl cluster-install
```

The chart keeps ClickHouse, Grafana, and the OTLP gateway private as
`ClusterIP` services. Tailscale ingress can be added when the cluster access
path is ready; edge Macs continue using the Compose collector.

<!-- Kubernetes Secret selection from ../apps/hnetctl/hnetctl -->

Set `HNET_KUBE_SECRET` to use a custom Secret name consistently with
`cluster-secrets`, `cluster-bootstrap`, `cluster-install`, and `cluster-template`.
When unset, installation preserves the chart's `secret.existingName` setting.

## Zsh client

Source the client after setting the local token and an optional safe project
label:

```zsh
export AGENT_TELEMETRY_INGEST_TOKEN=...
export AGENT_TELEMETRY_PROJECT=example-project
source /path/to/hnet/ops/clients/zsh/agent-telemetry.zsh
```

The client sends only command category, duration, exit code, and a safe project
label to the loopback collector. It never sends command text, arguments,
environment variables, output, or working directories.

## Dotfiles setup

Dotfiles setup events should emit OTLP to the local edge collector with the
same bearer token. The edge collector does not ingest local log files.

## Operations

<!-- status and backup behavior from ../apps/hnetctl/hnetctl and backup.sh -->

Status and log commands report an unavailable runtime without starting it.
Start Docker or Kubernetes explicitly before inspecting a stopped stack.
Backups and archives use the same Docker executable selection as other
`hnetctl` commands, including `TELEMETRY_DOCKER_BIN`. The standalone `backup.sh`
delegates to `hnetctl backup`.

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
