## Parent

[Operate the private Mac fleet through Kubernetes, Tailscale, and Temporal][parent]

## What to build

Create a minimal private Kubernetes path that an authorized operator can inspect from another Mac with `kubectl` and `k9s`. The path includes an OrbStack-hosted smoke workload, tailnet-only Kubernetes API access, workload logs, health, and resource metrics. Preserve an `hnetctl` or SSH diagnostic path when the Kubernetes API is unavailable.

## Acceptance criteria

- [ ] An authorized remote Mac can authenticate to the Kubernetes API over Tailscale without a public endpoint.
- [ ] `k9s` can display the smoke workload, its health, logs, events, and current CPU and memory usage.
- [ ] An unauthorized or non-tailnet client cannot reach the Kubernetes API.
- [ ] Tailscale and Kubernetes credentials are supplied through secret references rather than committed values.
- [ ] `hnetctl` documents or exposes a break-glass status check that does not depend on remote `k9s` access.
- [ ] The installation and teardown procedures are reproducible on a clean OrbStack Kubernetes environment.

## Blocked by

None - can start immediately.

[parent]: {{PARENT_URL}}
