def attributes: .attributes | map({key, value: (.value | .[] )}) | from_entries;
def masked_attributes:
  attributes | .model == "test-model-v1" and .["app.version"] == "****" and
  .["gen_ai.system"] == "service@example.invalid" and
  .["gen_ai.request.model"] == "****" and .["gen_ai.response.model"] == "****" and
  .["error.type"] == "****";

[.[].resourceSpans[]?.scopeSpans[].spans[]] as $spans |
[.[].resourceLogs[]?.scopeLogs[].logRecords[]] as $logs |
[.[].resourceMetrics[]?.scopeMetrics[].metrics[] |
  select(.name == "gen_ai.client.token.usage")] as $metrics |
([.[].resourceMetrics[]?.scopeMetrics[].metrics[]] | length) == 2 and
([.[].resourceMetrics[]?.scopeMetrics[].metrics[] | select(.name == "hnet.test.operations")] |
  length == 1 and .[0].unit == "{operation}" and .[0].gauge.dataPoints[0].asInt == "1") and
($spans | length) == 1 and ($logs | length) == 2 and ($metrics | length) == 1 and
($spans[0] |
  masked_attributes and .name == "agent.operation" and .status.code == 2 and
  .traceState == "test=span" and
  (.links | length) == 1 and .links[0].traceState == "test=linked" and
  (.links[0] | attributes | .["link.type"]) == "retry" and
  (.status.message // "") == "" and
  .startTimeUnixNano == "1700000000000000000" and
  .endTimeUnixNano == "1700000000001000000" and
  (attributes | .["gen_ai.usage.input_tokens"] == "42" and .["gen_ai.operation.name"] == "chat") and
  (.events | length) == 1 and .events[0].name == "agent.event" and
  (.events[0] | masked_attributes)) and
($logs[0] |
  masked_attributes and .eventName == "hnet.test.diagnostic" and
  .timeUnixNano == "1700000000000000000" and
  .observedTimeUnixNano == "1700000000001000000" and .severityNumber == 17 and .severityText == "ERROR" and
  (attributes | .["shell.duration_ms"] == "12" and .["shell.exit_code"] == "1")) and
($logs[0] | attributes | .input_tokens == "30" and .output_tokens == "8" and
  .cache_read_tokens == "12" and .cache_creation_tokens == "3") and
($logs[1] | .eventName == "codex.api_request" and .severityText == "ERROR" and
  (.severityNumber // 0) == 0 and .timeUnixNano == "1700000000000000000") and
($metrics[0] | .unit == "{token}" and .description == "Tokens used" and
  .metadata[0].value.stringValue == "test" and
  .sum.aggregationTemporality == 2 and .sum.isMonotonic == true and
  (.sum.dataPoints | length) == 1 and
  (.sum.dataPoints[0] | masked_attributes and .asInt == "42" and
    .exemplars[0].asInt == "42" and .exemplars[0].filteredAttributes[0].value.stringValue == "test" and
    .startTimeUnixNano == "1700000000000000000" and
    .timeUnixNano == "1700000000001000000")) and
([.[] | .resourceSpans[]?, .resourceLogs[]?, .resourceMetrics[]? |
  .resource | attributes | .["service.name"] == "hnet.test" and
  .originator == "hnet-test" and .["app.version"] == "****"] | all) and
([.[] | .resourceSpans[]?, .resourceLogs[]?, .resourceMetrics[]?] |
  all(.schemaUrl == "https://example.invalid/resource-schema")) and
([.[] | .resourceSpans[]?.scopeSpans[], .resourceLogs[]?.scopeLogs[], .resourceMetrics[]?.scopeMetrics[]] |
  all(.schemaUrl == "https://example.invalid/scope-schema" and
    (.scope.name | startswith("hnet.test.")) and .scope.version == "1.2.3"))
