# Telemetry redaction contract

Telemetry is default-deny. A field is forwarded only when the Mac edge collector
and Studio gateway allow it. Redaction errors drop the payload instead of
forwarding it unchanged.

## Stored fields

<!-- stored fields from collector/edge.yaml and collector/gateway.yaml -->

| Source | Stored fields                                                                                                       |
| ------ | ------------------------------------------------------------------------------------------------------------------- |
| zsh    | command category, duration, exit code, safe project label, host, timestamp                                          |
| agents | service, model, operation, token counts, session ID, status, safe tool name, duration, app version, host, timestamp |

## Never stored

- command lines or arguments
- environment variables
- stdout or stderr
- working directories or file paths
- prompts or completions
- tool arguments or results
- request or response bodies
- exception messages
- account identifiers
- terminal details

## Enforcement

1. The zsh hook converts the raw command to an allowlisted category in memory.
2. The Mac collector blanks log bodies and keeps only approved attributes.
3. Span and span-event names are normalized before export.
4. The Studio gateway applies the same allowlists before ClickHouse.
5. Both transforms use `error_mode: propagate`, so a transform failure drops the
   affected payload.

Unknown zsh executables are `other`; shell scripts are `script`. A project label
must match `[A-Za-z0-9][A-Za-z0-9._-]*` or it becomes `unlabeled`.

When a new panel needs another field, add it to both collector allowlists and
document it here before deployment.
