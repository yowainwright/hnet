CREATE DATABASE otel;

CREATE TABLE otel.otel_logs (
    Timestamp DateTime64(9),
    EventName String,
    ServiceName String,
    ResourceAttributes Map(String, String),
    LogAttributes Map(String, String),
    SeverityText String
) ENGINE = Memory;

CREATE TABLE otel.otel_traces (
    Timestamp DateTime64(9),
    SpanName String,
    ServiceName String,
    ResourceAttributes Map(String, String),
    SpanAttributes Map(String, String),
    StatusCode String
) ENGINE = Memory;

CREATE TABLE otel.otel_metrics_histogram (
    TimeUnix DateTime64(9),
    ServiceName String,
    Attributes Map(String, String),
    MetricName String,
    Sum Float64
) ENGINE = Memory;

INSERT INTO otel.otel_logs VALUES
('2026-01-01 00:01:00', 'sdk.event', 'codex_cli_rs', map('host.name', 'mac-studio'),
 map('event.name', 'codex.sse_event', 'event.kind', 'response.completed',
     'conversation.id', 'codex-fixture', 'model', 'codex-test',
     'input_token_count', '100', 'output_token_count', '20',
     'cached_token_count', '40', 'reasoning_token_count', '5'), 'INFO'),
('2026-01-01 00:02:00', 'sdk.event', 'codex_cli_rs', map('host.name', 'mac-studio'),
 map('event.name', 'codex.websocket_event', 'event.kind', 'response.completed',
     'conversation.id', 'codex-fixture', 'model', 'codex-test',
     'input_token_count', '50', 'output_token_count', '10'), 'INFO'),
('2026-01-01 00:03:00', 'claude_code.api_request', 'claude-code', map('host.name', 'mac-mini-1'),
 map('event.name', 'api_request', 'session.id', 'claude-fixture', 'model', 'claude-test',
     'input_tokens', '30', 'output_tokens', '8',
     'cache_read_tokens', '12', 'cache_creation_tokens', '3', 'duration_ms', '250'), 'INFO'),
('2026-01-01 00:04:00', '', 'claude-code', map('host.name', 'mac-mini-1'),
 map('event.name', 'api_request', 'session.id', 'claude-fixture', 'model', 'claude-test',
     'input_tokens', '0', 'output_tokens', '0'), 'INFO'),
('2026-01-01 00:05:00', 'sdk.event', 'codex_cli_rs', map('host.name', 'mac-studio'),
 map('event.name', 'codex.sse_event', 'event.kind', 'response.created',
     'input_token_count', '999', 'output_token_count', '999'), 'INFO'),
('2026-01-01 00:06:00', '', 'claude-code', map('host.name', 'mac-mini-1'),
 map('event.name', 'tool_result', 'session.id', 'claude-fixture', 'tool_name', 'Read',
     'duration_ms', '12', 'success', 'true', 'input_tokens', '999'), 'INFO'),
('2025-12-31 23:59:00', 'sdk.event', 'codex_cli_rs', map('host.name', 'mac-studio'),
 map('event.name', 'codex.sse_event', 'event.kind', 'response.completed',
     'model', 'codex-test', 'input_token_count', '999', 'output_token_count', '999'), 'INFO');

INSERT INTO otel.otel_metrics_histogram VALUES
('2026-01-01 00:01:00', 'codex_cli_rs', map('model', 'codex-test'), 'codex.turn.token_usage', 999),
('2026-01-01 00:02:00', 'codex_cli_rs', map('model', 'codex-test'), 'codex.turn.token_usage', 1998);
