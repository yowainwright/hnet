## Parent

[Operate the private Mac fleet through Kubernetes, Tailscale, and Temporal][parent]

## What to build

Prove that a selected telemetry archive can be restored without risking the active dataset. The drill retrieves and verifies a Restic snapshot, restores ClickHouse into an isolated environment, runs representative queries, records the result and duration, and cleans up explicitly.

## Acceptance criteria

- [ ] `hnetctl` can list eligible snapshots and start a restore drill for an explicitly selected snapshot.
- [ ] The restore target is isolated from production storage and cannot overwrite the active ClickHouse dataset by default.
- [ ] Snapshot integrity is verified before data is loaded.
- [ ] Representative count, time-range, and dashboard-source queries pass against the restored data.
- [ ] The drill records the snapshot identity, verification results, duration, and failure reason without sensitive payloads.
- [ ] The documented direct recovery path can perform the restore when Temporal is unavailable.
- [ ] Cleanup requires an explicit target and leaves the active telemetry deployment unchanged.

## Blocked by

- [Archive telemetry through a recoverable workflow][issue-07]

[issue-07]: {{ISSUE_07_URL}}
[parent]: {{PARENT_URL}}
