# Private Mac fleet epic bundle

This bundle creates one epic and ten native sub-issues for the private Mac fleet control plane.

## Contents

| Order | Issue | Blocked by |
| --- | --- | --- |
| Epic | Operate the private Mac fleet through Kubernetes, Tailscale, and Temporal | None |
| 1 | Operate a private Kubernetes smoke workload from remote k9s | None |
| 2 | Observe synthetic telemetry through Kubernetes | 1 |
| 3 | Run a durable health workflow from hnetctl | 1 |
| 4 | Build a reversible central telemetry cutover | 2 |
| 5 | Enroll one Mac as a managed fleet endpoint | 3, 4 |
| 6 | Show fleet presence and capacity through Valkey | 5 |
| 7 | Archive telemetry through a recoverable workflow | 3, 4 |
| 8 | Prove an archive with an isolated restore drill | 7 |
| 9 | Run an approved maintenance workflow on a managed Mac | 5, 7 |
| 10 | Recover the control plane without Temporal | 3, 8 |

## Labels

The publisher creates these labels when absent:

- `epic`
- `needs-info`
- `needs-triage`
- `ready-for-review`
- `ready-to-implement`

The epic and sub-issues are initially labeled `ready-for-review`. Move a reviewed, sufficiently detailed child issue to `ready-to-implement`.

## Publication

Publishing requires GitHub CLI 2.97 or newer and write access to `yowainwright/hnet`.

Preview the publication order without changing GitHub:

```bash
bash .github/issue-drafts/private-mac-fleet/publish.sh
```

Publish manually:

```bash
bash .github/issue-drafts/private-mac-fleet/publish.sh --publish
```

Set `GH_REPO` to publish into a different repository. The publisher reuses an exact-title match if a previous run stopped after creating some issues.
