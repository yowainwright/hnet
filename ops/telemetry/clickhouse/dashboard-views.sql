CREATE OR REPLACE VIEW otel.agent_events AS
WITH coalesce(nullIf(LogAttributes['event.name'], ''), EventName) AS semantic_event
SELECT
    Timestamp AS time,
    'log' AS signal,
    ServiceName AS client,
    if(ServiceName = 'claude-code' AND semantic_event != ''
       AND NOT startsWith(semantic_event, 'claude_code.'),
       concat('claude_code.', semantic_event), semantic_event) AS event,
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
    ) AS status,
    coalesce(
        nullIf(LogAttributes['gen_ai.response.model'], ''),
        nullIf(LogAttributes['gen_ai.request.model'], ''),
        nullIf(LogAttributes['model'], ''),
        ResourceAttributes['model']
    ) AS model
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
    StatusCode AS status,
    coalesce(
        nullIf(SpanAttributes['gen_ai.response.model'], ''),
        nullIf(SpanAttributes['gen_ai.request.model'], ''),
        nullIf(SpanAttributes['model'], ''),
        ResourceAttributes['model']
    ) AS model
FROM otel.otel_traces;

CREATE OR REPLACE VIEW otel.agent_calls AS
SELECT time, client, host, session, model
FROM otel.agent_events
WHERE event IN ('codex.api_request', 'codex.websocket_request', 'claude_code.api_request')
   OR operation IN ('chat', 'generate_content', 'text_completion');

CREATE OR REPLACE VIEW otel.agent_calls_5m AS
SELECT
    toStartOfInterval(time, INTERVAL 5 minute) AS time,
    client,
    count() AS calls
FROM otel.agent_calls
GROUP BY time, client;

CREATE OR REPLACE VIEW otel.agent_usage AS
WITH
    coalesce(nullIf(LogAttributes['event.name'], ''), EventName) AS semantic_event,
    semantic_event IN ('api_request', 'claude_code.api_request')
        AND (ServiceName = 'claude-code' OR startsWith(semantic_event, 'claude_code.')) AS is_claude_request,
    toUInt64OrNull(nullIf(LogAttributes['cache_read_tokens'], '')) AS cache_read,
    toUInt64OrNull(nullIf(LogAttributes['cache_creation_tokens'], '')) AS cache_creation
SELECT
    Timestamp AS time,
    ServiceName AS client,
    ResourceAttributes['host.name'] AS host,
    coalesce(
        nullIf(LogAttributes['gen_ai.conversation.id'], ''),
        nullIf(LogAttributes['conversation.id'], ''),
        LogAttributes['session.id']
    ) AS session,
    coalesce(
        nullIf(LogAttributes['gen_ai.response.model'], ''),
        nullIf(LogAttributes['gen_ai.request.model'], ''),
        nullIf(LogAttributes['model'], ''),
        nullIf(ResourceAttributes['model'], ''),
        'unknown'
    ) AS model,
    coalesce(
        toUInt64OrNull(nullIf(LogAttributes['gen_ai.usage.input_tokens'], '')),
        toUInt64OrNull(nullIf(LogAttributes['input_token_count'], '')),
        toUInt64OrNull(nullIf(LogAttributes['input_tokens'], ''))
            + coalesce(cache_read, 0) + coalesce(cache_creation, 0)
    ) AS input_tokens,
    coalesce(
        toUInt64OrNull(nullIf(LogAttributes['gen_ai.usage.output_tokens'], '')),
        toUInt64OrNull(nullIf(LogAttributes['output_token_count'], '')),
        toUInt64OrNull(nullIf(LogAttributes['output_tokens'], ''))
    ) AS output_tokens,
    coalesce(toUInt64OrNull(nullIf(LogAttributes['cached_token_count'], '')), cache_read) AS cached_input_tokens,
    cache_creation AS cache_creation_tokens,
    toUInt64OrNull(nullIf(LogAttributes['reasoning_token_count'], '')) AS reasoning_output_tokens,
    toUInt64OrNull(nullIf(LogAttributes['duration_ms'], '')) AS duration_ms
FROM otel.otel_logs
WHERE (is_claude_request OR (
    semantic_event IN ('codex.sse_event', 'codex.websocket_event')
    AND LogAttributes['event.kind'] = 'response.completed'
)) AND (input_tokens IS NOT NULL OR output_tokens IS NOT NULL);

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
WHERE lowerUTF8(status) IN ('error', 'fatal', 'false', 'failed')
   OR event = 'claude_code.api_error';

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
    coalesce(nullIf(LogAttributes['event.name'], ''), EventName) AS event,
    LogAttributes['tool_name'] AS tool,
    toUInt64OrZero(LogAttributes['duration_ms']) AS duration_ms,
    LogAttributes['success'] AS success
FROM otel.otel_logs
WHERE LogAttributes['tool_name'] != '';

CREATE OR REPLACE VIEW otel.dotfiles_installs AS
SELECT
    Timestamp AS time,
    ResourceAttributes['host.name'] AS host,
    LogAttributes['dotfiles.package'] AS package_name,
    LogAttributes['dotfiles.manager'] AS manager,
    LogAttributes['tool_name'] AS tool,
    LogAttributes['dotfiles.version'] AS version,
    toUInt64OrZero(LogAttributes['duration_ms']) AS duration_ms,
    LogAttributes['status'] AS status,
    LogAttributes['success'] AS success
FROM otel.otel_logs
WHERE LogAttributes['event.name'] = 'dotfiles.npm_global_install';

CREATE OR REPLACE VIEW otel.agent_hosts AS
SELECT
    host,
    max(time) AS last_seen,
    count() AS events
FROM otel.agent_events
WHERE host != ''
GROUP BY host;
