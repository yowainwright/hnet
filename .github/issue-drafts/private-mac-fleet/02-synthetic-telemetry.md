## Parent

[Operate the private Mac fleet through Kubernetes, Tailscale, and Temporal][parent]

## What to build

Prove the central telemetry path inside Kubernetes with a synthetic, privacy-safe OTLP event. The event must pass through the central collector, persist in ClickHouse, and appear in a provisioned Grafana view while every data service remains private to the cluster.

## Acceptance criteria

- [ ] The central collector, ClickHouse, and Grafana run in the `telemetry` namespace with observable health and resource usage.
- [ ] A deterministic synthetic event reaches the collector and can be queried from ClickHouse.
- [ ] The same event appears in a provisioned Grafana view accessible only through the tailnet.
- [ ] The synthetic payload satisfies the existing default-deny redaction contract and contains no private machine identifier.
- [ ] ClickHouse and the collector ingestion interfaces are not exposed publicly.
- [ ] An automated smoke check fails clearly at the first broken hop in the telemetry path.

## Blocked by

- [Operate a private Kubernetes smoke workload from remote k9s][issue-01]

[issue-01]: {{ISSUE_01_URL}}
[parent]: {{PARENT_URL}}
