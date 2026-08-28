## Parent

[Operate the private Mac fleet through Kubernetes, Tailscale, and Temporal][parent]

## What to build

Exercise recovery of the central control plane without relying on a running Temporal cluster. Starting from a clean local Kubernetes environment, an operator restores required configuration and secrets, recovers PostgreSQL and ClickHouse, reconnects the browser and API surfaces through Tailscale, and confirms that managed workers resume polling.

## Acceptance criteria

- [ ] A user-run recovery drill starts from a clean OrbStack Kubernetes environment with its destructive scope stated before execution.
- [ ] Repository configuration and approved secret references recreate the `telemetry`, `workflows`, and `platform` services.
- [ ] PostgreSQL and ClickHouse are restored from documented, verified recovery sources without an active Temporal service.
- [ ] Grafana, the Temporal UI, the Kubernetes API proxy, and required ingestion endpoints become reachable only through the tailnet.
- [ ] At least one managed Mac reconnects, resumes polling its typed queue, and refreshes fleet presence.
- [ ] `hnetctl` verifies central health, restored telemetry queries, and the direct break-glass paths.
- [ ] The drill records recovery duration, manual interventions, and unresolved recovery gaps without private infrastructure identifiers.

## Blocked by

- [Run a durable health workflow from hnetctl][issue-03]
- [Prove an archive with an isolated restore drill][issue-08]

[issue-03]: {{ISSUE_03_URL}}
[issue-08]: {{ISSUE_08_URL}}
[parent]: {{PARENT_URL}}
