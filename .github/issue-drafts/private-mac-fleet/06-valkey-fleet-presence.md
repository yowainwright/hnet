## Parent

[Operate the private Mac fleet through Kubernetes, Tailscale, and Temporal][parent]

## What to build

Show current fleet presence and capacity through expiring Valkey records. Managed workers publish privacy-safe heartbeats, and `hnetctl fleet status` presents the active label, role, state, capacity, and last-seen age without treating Valkey as durable inventory.

## Acceptance criteria

- [ ] Valkey runs as a private `ClusterIP` service in the `platform` namespace.
- [ ] The enrolled worker refreshes a TTL-backed heartbeat containing only an approved label, role, state, capacity summary, and timestamp.
- [ ] `hnetctl fleet status` shows active workers in a stable, human-readable format.
- [ ] A stopped or disconnected worker disappears after the configured TTL without manual cleanup.
- [ ] Restarting or clearing Valkey does not lose durable workflow state, enrollment authority, or required configuration.
- [ ] Valkey authentication is supplied through secret references and is not exposed to edge clients that do not need it.

## Blocked by

- [Enroll one Mac as a managed fleet endpoint][issue-05]

[issue-05]: {{ISSUE_05_URL}}
[parent]: {{PARENT_URL}}
