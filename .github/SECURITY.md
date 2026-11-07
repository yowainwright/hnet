# Security Policy

## Supported versions

`hnet` is maintained from its default branch and does not publish versioned
releases.

`VERSION` currently identifies a local release candidate, not a published or
supported release. macOS with Codex and Claude Code is the first release target.
Kubernetes and general ChatGPT conversation tracking remain experimental or
unverified. Publication and supported-release gates are tracked separately.

The trusted-Mac model includes same-user access to ingestion credentials through
login Keychain and inherited process environments. Per-device ingestion tokens
do not grant dashboard, database, or vault access. Locking 1Password does not
revoke an already enrolled token; revoke it centrally and refresh affected
collectors, Keychain entries, shells, and agents.

| Version | Supported |
| --- | --- |
| Default branch | Yes |
| Older revisions | No |

## Reporting a vulnerability

Do not open a public issue. Report vulnerabilities privately through a
[GitHub security advisory](https://github.com/yowainwright/hnet/security/advisories/new).
Include the affected component, impact, reproduction steps, and any suggested
mitigation. Do not include live credentials, private infrastructure details,
or captured telemetry.

The maintainer will acknowledge a report within 48 hours and begin an
investigation within five days. Disclosure and remediation timing will be
coordinated with the reporter.
