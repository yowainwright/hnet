# hnet

`hnet` makes the Mac Studio the main node for Jeff's home infrastructure and provides one private way to observe and operate it from the other Macs.

## Why this exists

The home network has several Macs doing related work, but there is no single operational view. The Mac Studio is the natural always-on host. The goal is to make it obvious what is running there, whether it is healthy, and how the rest of the Macs connect to it.

This project is also a practical place to learn Kubernetes and durable workflows through real home infrastructure rather than isolated examples.

## Current state

The repository already has a working telemetry system:

- Each Mac runs a local OpenTelemetry collector.
- Sanitized telemetry travels privately over Tailscale.
- The Mac Studio runs the central collector, ClickHouse, and Grafana with Docker Compose.
- `hnetctl` starts, inspects, backs up, and archives that stack.
- `agent-sync` configures agent tools on the Macs and already discovers machines through Tailscale.

The current Compose deployment is useful and should keep working while the next shape of the project is tested.

## Project shape

The Mac Studio is the main node and canonical deployment host. Git remains the recoverable source of truth, but only the Studio checkout deploys the central stack.

```text
Other Macs
  |-- k9s and hnetctl -----------|
  |-- local telemetry collector -|-- Tailscale --> Mac Studio
                                                  |-- hnet project root
                                                  |-- Kubernetes
                                                  |-- central telemetry
```

Other Macs are clients and workers. They are not Kubernetes nodes. They connect to the Studio through Tailscale and keep only the host-local services they need.

## First useful milestone

Run a small Kubernetes workload on the Mac Studio and inspect it with k9s from another Mac.

The milestone is complete when:

- The Studio runs the workload in OrbStack Kubernetes.
- Another authorized Mac reaches the Kubernetes API through Tailscale.
- k9s shows the workload, logs, events, health, and resource usage.
- No service is exposed publicly.
- The existing Compose telemetry stack is unchanged.

This milestone proves the basic operating model before the project moves any important service.

## Direction after the milestone

If the first milestone feels useful, move the central telemetry services from Compose to Kubernetes with a tested rollback path. k9s then becomes the single view for the central collector, ClickHouse, Grafana, and future services.

The following technologies are interesting but are not prerequisites:

- Temporal for typed operations that must survive retries, disconnects, or restarts.
- Valkey for short-lived fleet presence when a concrete view needs it.
- OpenTofu for external infrastructure that should be reproducible.
- An `hnet-ops` skill in `agent-sync` once `hnetctl` has stable commands worth exposing to agents.

They should enter the project only through a small, useful behavior—not as infrastructure added in advance.

## Boundaries

- The Studio is a single main node, not a highly available cluster.
- Tailscale is the private network boundary; there is no public ingress.
- 1Password is the source for resolved secrets.
- Private hostnames, IP addresses, tailnet names, credentials, and telemetry payloads do not belong in Git.
- Temporal must not become a generic remote shell.
- `agent-sync` distributes tools and agent instructions; `hnet` owns the running system.

## Not decided yet

The first milestone does not require decisions about Temporal workflow design, Valkey data structures, long-term backup retention, multi-node Kubernetes, or a complete agent skill. Those decisions can follow evidence from the running system.

## Existing documentation

- [Repository overview](../../README.md)
- [Telemetry architecture and operations](../telemetry/README.md)
- [Telemetry redaction contract](../telemetry/REDACTION.md)
