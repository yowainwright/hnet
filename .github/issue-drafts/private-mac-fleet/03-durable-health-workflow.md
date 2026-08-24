## Parent

[Operate the private Mac fleet through Kubernetes, Tailscale, and Temporal][parent]

## What to build

Add the first durable operation as a typed control-plane health workflow started and inspected through `hnetctl`. Temporal uses external PostgreSQL and a Go worker, survives a worker restart, and reports useful progress without recording secrets or sensitive payloads in workflow history.

## Acceptance criteria

- [ ] PostgreSQL, Temporal, its browser UI, and a Go worker run in the `workflows` namespace.
- [ ] `hnetctl` can start a typed health workflow and display its workflow identifier, state, and result.
- [ ] The workflow checks a fixed allowlist of central services and returns structured, privacy-safe health data.
- [ ] Retry, timeout, cancellation, and failure states are visible from `hnetctl` and the Temporal UI.
- [ ] An in-progress workflow completes after the worker is stopped and restarted.
- [ ] Workflow inputs, results, search attributes, and logs contain no credentials, private hostnames, IP addresses, or telemetry payloads.

## Blocked by

- [Operate a private Kubernetes smoke workload from remote k9s][issue-01]

[issue-01]: {{ISSUE_01_URL}}
[parent]: {{PARENT_URL}}
