# AGENTS.md

## Purpose

This repository manages hnet: private observability for trusted Macs. Agents
should optimize for safe operation, privacy preservation, and fast human
check-ins when work touches live infrastructure.

## Privacy Boundary

hnet keeps operational signal and excludes private work content. Do not add,
log, commit, or summarize:

- secret values or resolved 1Password values
- prompts, completions, request bodies, or response bodies
- shell command text, shell output, environment dumps, or raw paths
- account identifiers or host details beyond safe labels already used by the
  repo configuration

Use the example env files and existing redaction configs as the source of truth.
Local `.env*` files are ignored and may contain secret references.

## Default Workflow

Before editing, read the relevant local files and prefer existing repo patterns.
Keep changes scoped to the smallest operational surface that solves the task.

Use the root [README](README.md) for setup and operations. The
[hnet-setup skill](.agents/skills/hnet-setup/SKILL.md) guides central and edge
enrollment without duplicating those instructions.

Use `hnetctl` as the operational entrypoint. Inspect the intended role first:

```bash
./ops/apps/hnetctl/hnetctl status       # Central services
./ops/apps/hnetctl/hnetctl edge-status  # Local collection
```

For approved Compose startup, use `start` on the central host and
`client-install` for enrollment. `serve` changes private Tailscale forwarding.
`up` also bootstraps experimental Kubernetes; use it only when that is requested.

Use the interactive operator dashboard only when a human is present:

```bash
./ops/apps/hnetctl/hnetctl mprocs
```

Use k9s through `hnetctl` so the expected context and namespace are applied:

```bash
./ops/apps/hnetctl/hnetctl k9s pods
```

## Human Check-Ins

Default to progress without asking for routine code edits, read-only inspection,
or validation. Check in with the human before actions that change live state,
broaden access, or could discard data.

Ask before:

- deleting Kubernetes PVCs, Docker volumes, backups, or telemetry data
- changing Tailscale exposure, ingress, network policy, or public/private
  access boundaries
- changing redaction, retention, secret handling, or authentication behavior
- installing new system dependencies or introducing new runtime services
- running long-lived interactive TUIs from an agent-controlled shell
- making a broad refactor outside the files needed for the current task

For long sessions, send a short checkpoint after each meaningful milestone:

```text
Checkpoint:
- Done: what changed or what was verified
- Learned: important state, failure cause, or risk
- Next: the command or edit about to happen
- Human needed: approval, choice, secret entry, or "none"
```

If a command may affect live infrastructure, state the expected impact before
running it. If a command fails, report the failing component and the next
diagnostic step instead of switching strategies silently.

## Validation

Run focused tests for the changed surface. For general hnet operations changes,
use:

```bash
tests/ops/apps/hnetctl/hnetctl_test.sh
./ops/scripts/validate.sh
```

Useful live checks:

```bash
./ops/apps/hnetctl/hnetctl status
./ops/apps/hnetctl/hnetctl cluster-status
./ops/apps/hnetctl/hnetctl edge-status
```

Useful logs:

```bash
./ops/apps/hnetctl/hnetctl logs collector
./ops/apps/hnetctl/hnetctl logs grafana
./ops/apps/hnetctl/hnetctl edge-logs
```

## Operational Notes

- The central Compose stack and the Kubernetes central stack may both be up
  during the current operator workflow.
- The ClickHouse Kubernetes container needs the narrowly scoped capabilities in
  its chart template for startup on local Kubernetes runtimes.
- The edge Compose collector needs its data-init service so the non-root
  collector can write retry queue files.
- If a Helm hook job fails, inspect workload readiness and logs first. After the
  runtime pods are healthy, it is usually safe to delete only the failed hook
  Job and rerun `cluster-bootstrap`.

## Editing Rules

- Prefer `rg` for search and `apply_patch` for manual edits.
- Do not revert unrelated user changes in the working tree.
- Keep checked-in docs free of local tailnet hostnames, personal vault names,
  and resolved secret material.
- Preserve ASCII unless a touched file already requires Unicode.
