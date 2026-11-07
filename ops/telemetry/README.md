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

<!-- Compose listeners and networks from compose.mac-studio.yml and ../apps/hnetctl/hnetctl -->

The central host binds Grafana and the OTLP gateway to loopback. Tailscale Serve
provides private access. Do not enable Funnel or router port forwarding.

Grafana and the gateway join the existing egress network so Docker can publish
their loopback ports. This also gives the gateway outbound network access;
its configured export destination is ClickHouse. ClickHouse stays on the
internal telemetry network.

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

<!-- Grafana database access from clickhouse/users.xml, grafana/provisioning/datasources/clickhouse.yaml, and the isolated permission test -->

Grafana's database user has `SELECT` access to `otel.*` with `readonly = 1`.
Its dedicated profile permits only `max_execution_time` changes from 1 to 60
seconds, as required by the [Grafana ClickHouse client](https://grafana.com/docs/plugins/grafana-clickhouse-datasource/latest/configure/#required-settings-permissions).
The data source has an explicit 30-second query timeout inside that limit.
The [native client's five-second deadline margin](https://github.com/ClickHouse/clickhouse-go/blob/v2.47.0/context.go#L219-L225)
also fits inside the server limit. Restart Grafana after changing its provisioned
timeout so the plugin replaces cached connection settings.
Other setting changes, writes, and access to other databases remain denied.
The connection health check alone does not exercise this permission.

Verify the profile in an isolated, networkless database with temporary storage:

```bash
tests/ops/telemetry/clickhouse/grafana_permissions_test.sh
```

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

<!-- Zsh client setup and record fields from ../clients/zsh/agent-telemetry.zsh -->

Source the client after setting the local token and an optional safe project
label:

```zsh
export AGENT_TELEMETRY_INGEST_TOKEN=...
export AGENT_TELEMETRY_PROJECT=example-project
source /path/to/hnet/ops/clients/zsh/agent-telemetry.zsh
```

The client sends only a timestamp, command category, duration, exit code, and a
safe project label to the loopback collector. It never sends command text,
arguments, environment variables, output, or working directories.

## Automatic shell collection

<!-- enrollment, Keychain access, and startup behavior from ../apps/hnetctl/hnetctl and ../clients/zsh/auto.zsh -->

Set this up once on each Mac. New terminal windows and tabs then load the client
from zsh startup. hnet uses the Mac's local login Keychain for its ingestion
token; 1Password remains the source used during enrollment and rotation.
[1Password CLI authorization is per terminal](https://www.1password.dev/cli/app-integration-security),
so calling it from every startup would require repeated approvals.

### This Mac

With the edge collector already configured and running:

```bash
./ops/apps/hnetctl/hnetctl shell-enable
./ops/apps/hnetctl/hnetctl shell-status
```

Approve the 1Password prompt. The installer verifies the Keychain value before
appending one marked hnet block to `${ZDOTDIR:-$HOME}/.zshrc`. Repeating the
command refreshes the token without duplicating the block. The hnet checkout
must remain available at the enrolled location.

The default is the local `login.keychain-db`, service `hnet.zsh.ingest`, account
`local`. The item allows access through `/usr/bin/security`; it does not enable
the allow-all-applications option. The token is available to the shell while
running, so programs running as your user remain part of the trust boundary.
Locking Keychain does not revoke tokens already loaded into existing shells.

The loader quietly skips collection if Keychain is locked, the item is missing,
or its value is invalid. Unlock Keychain and open a new terminal to retry. It
does not call 1Password during ordinary terminal startup. Noninteractive shells
do not load this automatic client. Agent applications have separate settings.

### Another Mac

Use the [portable client installer](../clients/README.md) for a clean Mac. It
checks dependencies and sign-in/setup state, supports explicit Homebrew
installation of missing apps, and runs the existing enrollment commands below.
Build its transfer archive with `hnetctl client-bundle`. After installation,
run `hnetctl client-check --connection` from a new terminal.

<!-- Client prerequisites from ../apps/hnetctl/hnetctl, ../clients/zsh/agent-telemetry.zsh, and compose.edge.yml -->

Before running enrollment commands, install:

| Tool | Installation and setup |
| --- | --- |
| OrbStack or Docker Desktop | [Download OrbStack](https://orbstack.dev/download), launch it, and enable Start at login. It supplies Docker and Compose. |
| Tailscale | [Install Tailscale for Mac](https://tailscale.com/download/mac) and sign into the central Mac's trusted tailnet. |
| 1Password for Mac and 1Password CLI (`op`) | Follow the [CLI installation guide](https://www.1password.dev/cli/get-started), sign into the app, and enable Settings > Developer > Integrate with 1Password CLI. |
| Codex CLI (`codex`) | Follow the [Codex CLI guide](https://learn.chatgpt.com/docs/cli). The CLI must be on PATH because enrollment validates configuration with it, even for desktop use. |

macOS provides Bash, zsh, curl, `security`, `open`, and `pgrep`. Git is needed
when obtaining hnet through Git. Install Claude Code separately if this Mac
will also send Claude telemetry, and the ChatGPT/Codex desktop app if needed.

The bundle carries the same tested client code, including unpublished fixes,
and installs it at a stable location. It excludes private environment files,
credentials, queues, and telemetry. The remaining steps describe manual
enrollment from an existing checkout; the installer performs them for you.

1. Copy `.env.edge.example` to `.env.edge` only if the private file does not
   already exist. Edit that file locally; keep its token as a 1Password reference.
2. Set the upstream to the central Mac's Tailscale HTTPS name and the assigned
   port. Use the matching host label and token field:

   | Host label | Upstream port | 1Password token field |
   | --- | --- | --- |
   | `mac-studio` | `4318` | `mac-studio-token` |
   | `mac-mini-1` | `4319` | `mac-mini-1-token` |
   | `mac-mini-2` | `4320` | `mac-mini-2-token` |

   For the next Mac's existing slot, use `AGENT_TELEMETRY_HOST=mac-mini-1`,
   upstream `https://mac-studio.your-tailnet.ts.net:4319`, and that slot's
   1Password field. Replace the example DNS and vault with your private values.
   Carry over the approved personal-redaction setting from the central setup.
   Additional slots require central gateway configuration first.
3. Run from that Mac's checkout:

   ```bash
   ./ops/apps/hnetctl/hnetctl edge-start
   ./ops/apps/hnetctl/hnetctl shell-enable
   ./ops/apps/hnetctl/hnetctl shell-status
   ```

4. Open a new terminal and verify its events using the assigned host label.

Each Mac's shell still sends to `127.0.0.1:4318`; its edge configuration selects
the central destination. Do not reuse another Mac's token. The central Mac and
Tailscale must be reachable for delivery; the edge collector queues sanitized
events during brief outages.

### Verify, rotate, or remove

Open a new terminal and run `git status` from a checkout. In Grafana, select the
last 15 minutes, wait about 15 seconds, and look for `hnet.zsh` under the expected
host label. On the central Mac, the default dashboard is
<http://localhost:2021>. On another Mac, use the central Mac's private Tailscale
HTTPS dashboard. `shell-status` checks enrollment, while a visible event proves
delivery. Collector status is available through `hnetctl edge-status`.

After rotating a token in 1Password, recreate the edge collector with
`hnetctl edge-start`, update the matching central gateway credential, and rerun
`hnetctl shell-enable`. Open new terminals to load the refreshed value.

To remove shell collection, delete the block between `# >>> hnet zsh >>>` and
`# <<< hnet zsh <<<` from the startup file. Then remove the local Keychain item:

```bash
security delete-generic-password -a local -s hnet.zsh.ingest \
  "$HOME/Library/Keychains/login.keychain-db"
```

Close existing terminals to unload their hooks and token. If the startup file
is a symlink, the installer stops before changing credentials or files; integrate
the source entry through the tool that manages that startup file.

The startup location follows [zsh's documented startup rules](https://zsh.sourceforge.io/Doc/Release/Files.html).
Container startup follows [Docker's restart policy](https://docs.docker.com/engine/containers/start-containers-automatically/).

## Codex

<!-- Codex settings, authentication, and launch commands from ../clients/codex/config.toml, ../clients/zsh/codex.zsh, and ../apps/hnetctl/hnetctl -->

Complete shell enrollment on each Mac first, then run:

```bash
./ops/apps/hnetctl/hnetctl codex-enable
```

The installer appends one marked block to the user-level Codex configuration.
It preserves other settings and refuses to replace existing OTel configuration.
It validates the configuration with the installed Codex CLI. The checked-in
[template](../clients/codex/config.toml) sends logs, traces, and metrics to the
loopback collector using binary OTLP/HTTP.

The configuration sets `log_user_prompt`, `log_agent_responses`, and
`log_guardian_assessments` to `false`, and `tool_result.max_bytes` to `0`.
The existing collector allowlists and empty-body transforms still apply.
These controls follow the [OpenAI configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference).

Open a new terminal to load the launchers:

```bash
codex
```

For the desktop app, quit ChatGPT/Codex first, then launch it with:

```bash
codex-app
```

Use `chatgpt-app` to select ChatGPT desktop explicitly when the standalone Codex
app is also installed. Both commands supply telemetry credentials to the local
Codex runtime. Regular ChatGPT web and desktop conversations have no verified
per-model OTLP export in this setup; launching ChatGPT does not prove that those
conversations are tracked.

Use this launcher each time the desktop app is started. An already-running app
keeps its original environment, so opening another window does not reload the
telemetry credentials. The launcher refuses to reuse a running app; quit it
completely and run the launcher again. The app keeps its credentials for
subsequent Codex
sessions in that process. The launcher prefers the standalone Codex app when
installed; otherwise it opens ChatGPT's integrated Codex.

The launchers read the existing `hnet.zsh.ingest` Keychain item and set standard
`OTEL_EXPORTER_OTLP_*HEADERS` and loopback endpoint variables for their child
processes. macOS `open` inherits that environment; the launcher does not pass
valueless `--env NAME` flags, which discarded the values in the native handoff
regression test. Header values do not appear in command arguments,
configuration, or
the parent terminal's environment. Unlock login Keychain if a launcher cannot
read the item. Normal launches use no 1Password CLI calls.

Codex CLI 0.166.0 sent a literal header placeholder in a loopback override test using
the documentation's `${VARIABLE}` example. Standard OTLP environment headers
authenticated all three signal exporters in that installed runtime. The
launcher therefore supplies credentials through the environment rather than
putting placeholder or resolved credentials into TOML.

Verify the desktop handoff on a Mac without launching ChatGPT/Codex or sending
a model request:

```bash
tests/ops/clients/zsh/desktop_launch_test.sh
```

The test launches a temporary background probe app with fake credentials. It
checks the actual macOS environment handoff and removes its temporary files.

After updating dashboard view definitions on the central Mac, refresh them with
`hnetctl dashboard-refresh`. It reruns the existing schema container. The event
views prefer semantic `event.name` attributes over generic SDK event names.

### See Codex in Grafana

<!-- Grafana names and panel meanings from grafana/dashboards/agent-telemetry.json and clickhouse/dashboard-views.sql -->

1. Open [Agent usage and sessions](http://localhost:2021/d/agent-telemetry) on the
   central Mac, or its private Tailscale HTTPS dashboard from another Mac.
2. Sign in using the Grafana credentials in 1Password.
3. Select **Last 15 minutes** and refresh. Allow about 15 seconds for event
   delivery. Use **Emitted event inventory** to see the actual client names.
4. Check **Recent sessions** and **Hosts and last seen**. After a normal model
   turn completes, check **Usage by model**, **Input tokens**, **Output tokens**,
   **Cached input tokens**, **Tokens over time**, and **Recent model usage**.
   Allow the logs batch to export. A session-start test alone produces no usage.

**Model calls** counts HTTP and WebSocket request events, Claude Code API
requests, and chat operations from supported agent traces. Session-start events
are excluded from that count. **Recent sessions** also lists reported models.

<!-- Token accounting from clickhouse/dashboard-views.sql and grafana/dashboards/agent-telemetry.json -->

Usage comes from Codex `response.completed` SSE/WebSocket events and Claude
Code `api_request` events. Metric snapshots are excluded from usage totals so
the same response is not counted through both logs and metrics. Unknown models
are labeled `unknown`; missing usage remains empty instead of inventing counts.

Input includes cache reads and cache creation. Claude's native `input_tokens`
excludes both, so hnet adds them to match the inclusive input convention.
Cached input and cache creation are input subsets. Reasoning is an output
subset; do not add these subsets to input/output totals again. The panels show
usage, not subscription charges. See [Codex telemetry](https://learn.chatgpt.com/docs/config-file/config-advanced#observability-and-telemetry)
and [Claude's token definitions](https://code.claude.com/docs/en/monitoring-usage#map-input-tokens-to-opentelemetry-genai-semantic-conventions).

### Rotate or remove Codex integration

After rotating the Mac's ingestion token, update the collectors as described
above and rerun `hnetctl shell-enable`. New CLI processes read the refreshed
Keychain item. Quit and relaunch the desktop app with `codex-app` to refresh its
environment too.

To disable this integration, remove the block between `# >>> hnet codex >>>`
and `# <<< hnet codex <<<` from the user-level Codex configuration, then restart
Codex. New terminals stop installing the hnet Codex functions when that marker
is absent. Existing terminals can be closed to unload their functions. The
shell client and its Keychain item have their separate removal procedure above.

## Claude Code

<!-- Claude launcher and startup from ../apps/hnetctl/hnetctl, ../clients/zsh/claude.zsh, and ../clients/zsh/auto.zsh -->

Install Claude Code separately and complete shell enrollment. Open a new
terminal and run:

```bash
claude
```

The interactive zsh function invokes `hnetctl claude`. Outside that shell,
use `./ops/apps/hnetctl/hnetctl claude`. This enables native OTLP/HTTP protobuf
logs and metrics to the local edge collector, with authentication read from
the existing login Keychain item. No token is stored in Claude configuration
or arguments. Ordinary launches do not call 1Password.

The launcher removes content opt-ins for prompts, assistant responses, tool
details/content, raw API bodies, and managed settings. Beta tracing is disabled.
Both collectors retain only the allowed operational metadata, including
`input_tokens`, `output_tokens`, `cache_read_tokens`, and `cache_creation_tokens`.
Bodies and other attributes are still removed before local buffering.

Complete one normal Claude Code turn, then check **Usage by model** and
**Recent model usage** in the last 15 minutes. Logs normally export every five
seconds and metrics every minute. `claude --version` checks the launcher but
does not produce token usage. Existing Claude processes must be restarted to
receive the launcher environment. Settings managed by an administrator can
override local exporter configuration; verify delivered events after launch.

This integration covers Claude Code, including its terminal CLI. It does not
configure regular Claude desktop/web chat. The configuration follows
[Claude Code's monitoring guide](https://code.claude.com/docs/en/monitoring-usage).

To bypass the launcher, run the installed CLI directly with `command claude`.
Token rotation follows the shell enrollment procedure.

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

Live ClickHouse telemetry has a configurable 14-day TTL; deletion occurs during
merges rather than exactly at the age boundary. Keep backup retention separate
and test restores periodically.

<!-- Snapshot maintenance from retention.sh, snapshot-retention.jq, and .env.restic.nas.example -->

`BACKUP_RETENTION_DAYS` in the Restic profile defaults to `30` and accepts
`1..36500`. Preview expiration without deleting snapshots:

```sh
./ops/apps/hnetctl/hnetctl retention nas
```

Selection uses wall-clock snapshot age and the `agent-telemetry` tag, including
an old newest snapshot when backups have stopped. After reviewing a dry run and
verifying a restore, an operator can explicitly run `retention nas --apply` to
forget selected snapshots, prune unreferenced data, and check the repository.
No maintenance schedule is enabled automatically. Local ClickHouse backup
staging is preserved and needs a separate reviewed cleanup policy. Snapshot
age does not bound the age of contained telemetry, and physical deletion depends
on pruning and other snapshots that reference the same data.

Durable Collector queues currently have no strict queued-record age cap. The
24-hour target remains a supported-release blocker; `max_elapsed_time` is not a
substitute. Live TTL, queue age, backup snapshot age and maintenance delays are
separate policies. No existing data or running retention configuration is
changed by installing the tooling.
