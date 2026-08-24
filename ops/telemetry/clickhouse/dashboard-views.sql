CREATE OR REPLACE VIEW otel.agent_events AS
SELECT
    Timestamp AS time,
    'log' AS signal,
    ServiceName AS client,
    coalesce(nullIf(EventName, ''), LogAttributes['event.name']) AS event,
    '' AS operation,
    ResourceAttributes['host.name'] AS host,
    coalesce(
        nullIf(LogAttributes['gen_ai.conversation.id'], ''),
        nullIf(LogAttributes['conversation.id'], ''),
        nullIf(LogAttributes['session.id'], ''),
        ''
    ) AS session,
    coalesce(
        nullIf(LogAttributes['success'], ''),
        nullIf(LogAttributes['status'], ''),
        SeverityText
    ) AS status
FROM otel.otel_logs
UNION ALL
SELECT
    Timestamp AS time,
    'trace' AS signal,
    ServiceName AS client,
    SpanName AS event,
    SpanAttributes['gen_ai.operation.name'] AS operation,
    ResourceAttributes['host.name'] AS host,
    coalesce(
        nullIf(SpanAttributes['gen_ai.conversation.id'], ''),
        nullIf(SpanAttributes['conversation.id'], ''),
        nullIf(SpanAttributes['session.id'], ''),
        ''
    ) AS session,
    StatusCode AS status
FROM otel.otel_traces;

CREATE OR REPLACE VIEW otel.agent_calls AS
SELECT time, client, host, session
FROM otel.agent_events
WHERE event = 'codex.api_request'
   OR operation IN ('chat', 'generate_content', 'text_completion');

CREATE OR REPLACE VIEW otel.agent_calls_5m AS
SELECT
    toStartOfInterval(time, INTERVAL 5 minute) AS time,
    client,
    count() AS calls
FROM otel.agent_calls
GROUP BY time, client;

CREATE OR REPLACE VIEW otel.agent_tokens_5m AS
SELECT
    toStartOfInterval(TimeUnix, INTERVAL 5 minute) AS time,
    ServiceName AS client,
    coalesce(
        nullIf(Attributes['gen_ai.token.type'], ''),
        nullIf(Attributes['token_type'], ''),
        nullIf(Attributes['type'], ''),
        'total'
    ) AS token_type,
    sum(Sum) AS tokens
FROM otel.otel_metrics_histogram
WHERE positionCaseInsensitive(MetricName, 'token') > 0
GROUP BY time, client, token_type;

CREATE OR REPLACE VIEW otel.agent_sessions AS
SELECT
    session,
    any(client) AS client,
    any(host) AS host,
    min(time) AS started,
    max(time) AS last_seen,
    count() AS events
FROM otel.agent_events
WHERE session != ''
GROUP BY session;

CREATE OR REPLACE VIEW otel.agent_inventory AS
SELECT signal, client, event, count() AS events
FROM otel.agent_events
GROUP BY signal, client, event;

CREATE OR REPLACE VIEW otel.agent_errors AS
SELECT time, client, host, session, status, event
FROM otel.agent_events
WHERE lowerUTF8(status) IN ('error', 'fatal', 'false', 'failed');

CREATE OR REPLACE VIEW otel.agent_shell_commands AS
SELECT
    Timestamp AS time,
    ResourceAttributes['host.name'] AS host,
    LogAttributes['shell.command.category'] AS category,
    LogAttributes['shell.project'] AS project,
    toUInt64OrZero(LogAttributes['shell.duration_ms']) AS duration_ms,
    toInt32OrZero(LogAttributes['shell.exit_code']) AS exit_code
FROM otel.otel_logs
WHERE LogAttributes['event.name'] = 'shell.command';

CREATE OR REPLACE VIEW otel.agent_tool_calls AS
SELECT
    Timestamp AS time,
    ServiceName AS client,
    ResourceAttributes['host.name'] AS host,
    coalesce(
        nullIf(LogAttributes['gen_ai.conversation.id'], ''),
        nullIf(LogAttributes['conversation.id'], ''),
        nullIf(LogAttributes['session.id'], ''),
        ''
    ) AS session,
    coalesce(nullIf(EventName, ''), LogAttributes['event.name']) AS event,
    LogAttributes['tool_name'] AS tool,
    toUInt64OrZero(LogAttributes['duration_ms']) AS duration_ms,
    LogAttributes['success'] AS success
FROM otel.otel_logs
WHERE LogAttributes['tool_name'] != '';

CREATE OR REPLACE VIEW otel.agent_hosts AS
SELECT
    host,
    max(time) AS last_seen,
    count() AS events
FROM otel.agent_events
WHERE host != ''
GROUP BY host;
