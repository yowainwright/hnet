# Install hnet on another Mac

<!-- Installer, checks, and bundle contents from ../../install.sh, ../apps/hnetctl/client.sh, Brewfile, and files.txt -->

Each Mac runs a local collector and the agent launchers. The central Mac keeps
Grafana and ClickHouse. This installer uses the existing Compose collector,
macOS login Keychain, and user-level Codex configuration.

## Package lifecycle

<!-- Packaged enrollment and startup from ../apps/hnetctl/client.sh, launcher.sh, and zsh/auto.zsh -->

The Homebrew package is a local preview. Its launcher uses the stable `opt/hnet`
path and current `share/hnet` support files. Installation alone does not enroll
the Mac or start services. After package installation, enrollment is explicit:

```sh
hnetctl client-install
hnetctl client-check --connection
```

Private enrollment state remains under `~/.local/share/hnet/ops/telemetry`.
An existing archive installation can be migrated by running the packaged
`client-install` with the same `--prefix`; it preserves the configuration and
managed startup entry. Review the displayed setup before approval. Existing
unmanaged/symlinked installations still require manual integration.

After an upgrade, new launcher calls select current package code. Open a new
terminal and fully quit/relaunch desktop agents to refresh loaded code. Running
collectors keep their existing mounted configuration until explicitly recreated;
an upgrade does not restart them. Review release notes and perform that rollout
separately when configuration changes.

Uninstall removes package code and preserves private configuration, queues,
backups and credentials. The managed startup shim quietly skips a removed
package. Revoke the device token centrally when retiring a Mac; stop the edge
collector explicitly and remove the marked hnet startup block after review.
Keychain token removal and private-data deletion are separate explicit actions.
Retain the previous package for rollback; no automatic cleanup discards state.

Keychain permits automatic collection within the same-user trust boundary:
programs running as you can retrieve or inherit the ingestion token. 1Password
is used for enrollment; locking it does not revoke an enrolled token. Each Mac
uses a separate ingestion token. Test rotation with synthetic credentials first,
then update the central and affected edge credentials, recreate those collectors,
refresh `shell-enable`, and relaunch shells and agents. Old-token rejection must
be verified before declaring the rotation complete.

## Archive installation

For central setup from a Homebrew package preview, create private configuration
outside the package before starting services:

```sh
state="${HNET_CLIENT_HOME:-$HOME/.local/share/hnet}/ops/telemetry"
install -d -m 700 "$state"
test -e "$state/.env.mac-studio" || cp \
  "$(brew --prefix hnet)/share/hnet/ops/telemetry/.env.mac-studio.example" \
  "$state/.env.mac-studio"
chmod 600 "$state/.env.mac-studio"
```

Edit that private file with the deployment's tailnet address and 1Password
references. Finish Docker/Tailscale/1Password sign-in first. `hnetctl start`
starts the central Compose stack; `hnetctl serve` explicitly configures private
Tailnet forwarding. Review that exposure before running it. Package support is
limited to Compose; experimental operator/Kubernetes commands use a checkout.
The Synology profile belongs at `$state/.env.restic.nas`; use the shipped example
and follow the [backup guide](../telemetry/README.md).

### Client archive steps

1. Transfer `hnet-client-macos.tar.gz` and its `.sha256` file to the new Mac.
   The bundle is built from the current working code, including unpublished
   client fixes. It contains only the explicit client file list: no private
   environment files, credentials, telemetry, queues, or central services.
2. In Terminal, from the folder containing the download:

   ```sh
   shasum -a 256 -c hnet-client-macos.tar.gz.sha256
   tar -xzf hnet-client-macos.tar.gz
   cd hnet-client
   ./install.sh --install-deps
   ```

   `--install-deps` asks permission to install missing prerequisites with an
   existing Homebrew installation. It preserves existing Docker Desktop or
   OrbStack, Tailscale, 1Password, and Codex installations and disables automatic
   upgrades. If Homebrew is missing, install it from <https://brew.sh> or install
   the prerequisites using their vendor installers, then run `./install.sh`.
3. Finish the one-time app setup when requested: start OrbStack/Docker, enable
   Start at login, sign into Tailscale, and unlock 1Password. In 1Password, turn
   on **Settings > Developer > Integrate with 1Password CLI**. Sign into Codex
   CLI with `codex login`. Then rerun `./install.sh`.
4. Enter the enrollment values when prompted:

   | Slot | Central HTTPS port | 1Password field |
   | --- | --- | --- |
   | `mac-mini-1` | `4319` | `mac-mini-1-token` |
   | `mac-mini-2` | `4320` | `mac-mini-2-token` |

   Use an unused slot. The upstream is the central Mac's private Tailscale
   HTTPS address with that port, for example
   `https://mac-studio.your-tailnet.ts.net:4319`. Supply a reference such as
   `op://YOUR_VAULT/agent-telemetry/mac-mini-1-token`, not the resolved token.
   Enter the approved additional personal-redaction pattern or its 1Password
   reference if one is used. The default `a^` adds no personal matches; the
   standard content allowlist and credential redaction remain active.

   Find the actual values on the central Mac in its private
   `ops/telemetry/.env.mac-studio` file: `TAILSCALE_DNS_NAME` supplies the host
   for the HTTPS URL; the matching `AGENT_TELEMETRY_MAC_MINI_1_TOKEN` or
   `AGENT_TELEMETRY_MAC_MINI_2_TOKEN` entry supplies the 1Password reference.
   Carry over `AGENT_TELEMETRY_REDACT_PATTERN` when configured. Copy those
   reference/settings values into the prompts, not resolved credentials.
5. Approve the displayed client setup. The installer verifies the upstream
   credential with an empty OTLP request before changing enrollment. It copies
   the code into `~/.local/share/hnet`, starts the edge collector, enrolls the
   shell, and configures Codex. The resolved token is kept out of configuration
   files and command arguments; it follows the existing Keychain/collector
   credential handling.
6. Open a new terminal:

   ```sh
   hnetctl client-check --connection
   codex
   ```

   Complete a normal turn and verify the assigned host and model in the
   existing Grafana dashboard on the central Mac. To view it from the new Mac,
   use the central Mac's Tailscale HTTPS dashboard address on port 443; the
   collector's assigned port is for ingestion, not the dashboard.
   For desktop use, fully quit the app first and launch it with `codex-app` or
   `chatgpt-app`. Claude Code is optional and uses the `claude` launcher when
   installed. The source download can be removed after installation; keep the
   installed directory in place.

## Check or repeat setup

```sh
./install.sh --check --prerequisites
./install.sh --check
```

The first command checks tools, local Docker/Compose, Tailscale connection,
1Password app/CLI presence, and Codex login/configuration. The second also
checks enrollment and collector health. Ordinary checks do not install or
start anything and do not resolve the ingestion token. `--connection` reads
the existing Keychain token and checks both collector endpoints without
creating usage records.

For a preconfigured deployment, put the four keys from
`ops/telemetry/.env.edge.example` into a private file and run:

```sh
./install.sh --config /path/to/private-enrollment.env
```

Use `--prefix /absolute/directory` to choose a different stable installation
location. Repeating setup preserves existing enrollment and other Codex and
shell settings. Conflicting Codex telemetry, startup symlinks, unmanaged
destination files, checksum failures, and remote Docker contexts stop setup
with an actionable error. `--yes` explicitly approves the displayed setup
without terminal confirmation; it does not bypass prerequisite checks.

## Build the transfer bundle

From the working hnet repository:

```sh
./ops/apps/hnetctl/hnetctl client-bundle
```

The archive and checksum are written to `dist/`. They use the current files,
so committing or publishing is not needed to test a second Mac. The archive
includes `SHA256SUMS`; setup checks it before installation.

Dependency installation uses [Homebrew Bundle](https://docs.brew.sh/Brew-Bundle-and-Brewfile)
and the small client Brewfile. The required tools are [OrbStack](https://orbstack.dev/download)
or Docker Desktop, [Tailscale](https://tailscale.com/download/mac),
[1Password for Mac and its CLI](https://www.1password.dev/cli/get-started), and
[Codex CLI](https://learn.chatgpt.com/docs/cli). macOS supplies the shell and
Keychain utilities used by setup. The developer Git-hook script is separate.
