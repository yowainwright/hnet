## Parent

[Operate the private Mac fleet through Kubernetes, Tailscale, and Temporal][parent]

## What to build

Enroll one trusted Mac as a managed fleet endpoint. A launchd-managed Go worker polls a typed Temporal task queue over Tailscale, runs an allowlisted diagnostic, and returns a structured result. The Mac remains a normal tailnet device rather than becoming a Kubernetes node.

## Acceptance criteria

- [ ] Enrollment assigns a safe host label and explicit worker role without committing a hostname, IP address, or tailnet name.
- [ ] Worker credentials are retrieved from an approved secret source and never written to workflow history.
- [ ] The launchd service starts after login or reboot and recovers from a worker process failure.
- [ ] `hnetctl` can target the enrolled label with a typed diagnostic and display its result.
- [ ] The worker exposes no generic shell, arbitrary script, or arbitrary argument activity.
- [ ] Revoking enrollment stops new work while standard SSH over Tailscale remains available for break-glass access.

## Blocked by

- [Run a durable health workflow from hnetctl][issue-03]
- [Build a reversible central telemetry cutover][issue-04]

[issue-03]: {{ISSUE_03_URL}}
[issue-04]: {{ISSUE_04_URL}}
[parent]: {{PARENT_URL}}
