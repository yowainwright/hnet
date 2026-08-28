## Parent

[Operate the private Mac fleet through Kubernetes, Tailscale, and Temporal][parent]

## What to build

Add an approved maintenance operation that restarts a managed Mac's edge telemetry collector and verifies recovery. The workflow targets a safe host label, pauses for explicit approval, runs a fixed activity with preflight and postflight checks, and exposes cancellation and audit state.

## Acceptance criteria

- [ ] `hnetctl` can request a collector restart for one enrolled host label and show the exact typed operation awaiting approval.
- [ ] No worker action begins until an authorized operator explicitly approves the workflow.
- [ ] The activity validates current collector state, performs an idempotent restart, and verifies healthy ingestion afterward.
- [ ] Cancellation before approval performs no host mutation; timeout or failure after approval reports the last safe state.
- [ ] The request, approval, execution, and result are visible in Temporal without recording private host data or credentials.
- [ ] The worker accepts no arbitrary command, service name, path, environment value, or script content.
- [ ] A documented SSH break-glass procedure can diagnose or recover the collector if the workflow cannot complete.

## Blocked by

- [Enroll one Mac as a managed fleet endpoint][issue-05]
- [Archive telemetry through a recoverable workflow][issue-07]

[issue-05]: {{ISSUE_05_URL}}
[issue-07]: {{ISSUE_07_URL}}
[parent]: {{PARENT_URL}}
