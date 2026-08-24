## Parent

[Operate the private Mac fleet through Kubernetes, Tailscale, and Temporal][parent]

## What to build

Coordinate a verified telemetry archive with Temporal. `hnetctl` starts a typed workflow that creates a ClickHouse backup, writes it through Restic to an OpenTofu-managed B2 destination, verifies the resulting snapshot, and reports durable progress and failure details.

## Acceptance criteria

- [ ] OpenTofu can preview and provision the archive bucket and retention policy without placing resolved credentials in configuration, plans, or state output.
- [ ] `hnetctl` starts an archive workflow with a generated or validated archive name and reports its progress.
- [ ] The workflow creates a consistent ClickHouse backup, archives it with Restic, and verifies the remote snapshot before succeeding.
- [ ] Retries are idempotent and cannot silently replace or duplicate a completed archive.
- [ ] Timeout, cancellation, and partial-failure states leave enough information for a safe retry or manual recovery.
- [ ] Storage and encryption credentials come from the approved secret system and never enter workflow history.

## Blocked by

- [Run a durable health workflow from hnetctl][issue-03]
- [Build a reversible central telemetry cutover][issue-04]

[issue-03]: {{ISSUE_03_URL}}
[issue-04]: {{ISSUE_04_URL}}
[parent]: {{PARENT_URL}}
