SELECT throwIf(count() != 4, 'Only completed responses belong in usage')
FROM otel.agent_usage
WHERE time >= '2026-01-01 00:00:00' AND time <= '2026-01-01 01:00:00';

SELECT throwIf(sum(input_tokens) != 195 OR sum(output_tokens) != 38,
    'Usage must include Codex and Claude without counting metric snapshots')
FROM otel.agent_usage
WHERE time >= '2026-01-01 00:00:00' AND time <= '2026-01-01 01:00:00';

SELECT throwIf(sum(cached_input_tokens) != 52 OR sum(cache_creation_tokens) != 3
    OR sum(reasoning_output_tokens) != 5, 'Cache and reasoning are separate subsets')
FROM otel.agent_usage
WHERE time >= '2026-01-01 00:00:00' AND time <= '2026-01-01 01:00:00';

SELECT throwIf(countIf(model = 'codex-test') != 2 OR countIf(model = 'claude-test') != 2,
    'Usage must retain model metadata')
FROM otel.agent_usage
WHERE time >= '2026-01-01 00:00:00' AND time <= '2026-01-01 01:00:00';

SELECT throwIf(countIf(event = 'claude_code.api_request') != 2,
    'Claude short event names need the client namespace')
FROM otel.agent_events;

SELECT throwIf(countIf(event = 'sdk.event') != 0,
    'Semantic event attributes must take precedence over SDK names')
FROM otel.agent_events;
