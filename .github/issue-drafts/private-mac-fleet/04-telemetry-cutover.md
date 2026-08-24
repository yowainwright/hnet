## Parent

[Operate the private Mac fleet through Kubernetes, Tailscale, and Temporal][parent]

## What to build

Move the existing central telemetry deployment to Kubernetes without creating a one-way cutover. Existing edge collectors must be able to send sanitized telemetry to the Kubernetes gateway, while the current Compose deployment remains a tested rollback target until the migration is accepted.

## Acceptance criteria

- [ ] Existing collector, ClickHouse, Grafana, dashboard provisioning, retention, and redaction behavior are represented in the Kubernetes deployment.
- [ ] At least one existing edge collector can send telemetry through Tailscale to the Kubernetes gateway.
- [ ] Kubernetes and Compose produce equivalent representative ClickHouse queries and Grafana views.
- [ ] A verified backup is taken before switching the central endpoint.
- [ ] The endpoint can be returned to Compose using a documented rollback procedure.
- [ ] A rollback drill preserves ingestion and confirms that no committed configuration contains resolved secrets or private network identifiers.

## Blocked by

- [Observe synthetic telemetry through Kubernetes][issue-02]

[issue-02]: {{ISSUE_02_URL}}
[parent]: {{PARENT_URL}}
