def attributes: .attributes | map({key, value: (.value | .[] )}) | from_entries;

[.[].resourceSpans[]?.scopeSpans[].spans[]] as $spans |
[.[].resourceLogs[]?.scopeLogs[].logRecords[]] as $logs |
[.[].resourceMetrics[]?.scopeMetrics[].metrics[] |
  select(.name == "gen_ai.client.token.usage")] as $metrics |
($spans | length) == 1 and ($logs | length) == 1 and ($metrics | length) == 1 and
($spans[0] |
  .name == "agent.operation" and .status.code == 2 and
  (.status.message // "") == "" and
  .startTimeUnixNano == "1700000000000000000" and
  .endTimeUnixNano == "1700000000001000000" and
  (attributes | .["gen_ai.usage.input_tokens"] == "42" and .["gen_ai.operation.name"] == "chat") and
  (.events | length) == 1 and .events[0].name == "agent.event") and
($logs[0] |
  .timeUnixNano == "1700000000000000000" and
  .observedTimeUnixNano == "1700000000001000000" and .severityNumber == 17 and
  (attributes | .["shell.duration_ms"] == "12" and .["shell.exit_code"] == "1")) and
($metrics[0] | .unit == "{token}" and
  .sum.aggregationTemporality == 2 and .sum.isMonotonic == true and
  (.sum.dataPoints | length) == 1 and
  (.sum.dataPoints[0] | .asInt == "42" and
    .startTimeUnixNano == "1700000000000000000" and
    .timeUnixNano == "1700000000001000000")) and
([.[] | .resourceSpans[]?, .resourceLogs[]?, .resourceMetrics[]? |
  .resource | attributes | .["service.name"]] | all(. == "hnet.test"))
