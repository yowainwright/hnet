# Contributing

## Development setup

Install these tools:

- Docker with Docker Compose
- ShellCheck
- Zsh

Clone the repository and work from its root. Copy the relevant example
environment file before running services locally. Never commit resolved
credentials, private hostnames, IP addresses, tailnet names, telemetry data,
backups, queues, or machine-specific environment files.

## Workflow

1. Create a focused branch.
2. Make the smallest coherent change.
3. Preserve the privacy rules in `ops/telemetry/REDACTION.md`.
4. Run the validation commands below.
5. Open a pull request describing the change and its operational impact.

## Style

- Keep shell functions short and single-purpose.
- Prefer immutable values and early returns.
- Quote shell expansions and fail securely.
- Keep deployment configuration explicit and host-neutral.
- Update documentation when behavior or operations change.

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

## Pull requests

Keep pull requests focused, link related issues, and include validation results.
Call out changes to deployment, retention, redaction, permissions, or backup
behavior explicitly.
