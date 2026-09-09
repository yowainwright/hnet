# Extend the original error-status regression with synthetic content only.
def private($field): "synthetic-private-" + $field;
def attribute($key; $value): {key: $key, value: {stringValue: $value}};
def denied($field): attribute("private.content"; private($field));
def scope($signal): {
  name: private($signal + "-scope-name"),
  version: private($signal + "-scope-version"),
  attributes: [denied($signal + "-scope-attribute")]
};
def resource($signal): {attributes: [
  attribute("service.name"; "hnet.test"),
  attribute("originator"; private($signal + "-resource-value")),
  denied($signal + "-resource-attribute")
]};
def attributes($signal): [
  attribute("gen_ai.operation.name"; "chat"),
  attribute("model"; private($signal + "-allowed-value")),
  denied($signal + "-attribute")
];

.resourceSpans[0].resource = resource("trace") |
.resourceSpans[0].schemaUrl = private("trace-resource-schema") |
.resourceSpans[0].scopeSpans[0].schemaUrl = private("trace-scope-schema") |
.resourceSpans[0].scopeSpans[0].scope = scope("trace") |
.resourceSpans[0].scopeSpans[0].spans[0] |= (
  .name = private("span-name") |
  .traceState = "test=" + private("span-trace-state") |
  .attributes = attributes("span") + [
    {key: "gen_ai.usage.input_tokens", value: {intValue: "42"}}
  ] |
  .events = [{
    timeUnixNano: "1700000000000000000", name: private("event-name"),
    attributes: attributes("event")
  }] |
  .links = [{
    traceId: "00000000000000000000000000000002", spanId: "0000000000000002",
    traceState: ("test=" + private("link-trace-state")),
    attributes: [denied("link-attribute")]
  }]
),
{
  resourceLogs: [{
    resource: resource("log"), schemaUrl: private("log-resource-schema"),
    scopeLogs: [{
      scope: scope("log"), schemaUrl: private("log-scope-schema"),
      logRecords: [{
        timeUnixNano: "1700000000000000000",
        observedTimeUnixNano: "1700000000001000000",
        severityNumber: 17, severityText: private("log-severity"),
        eventName: private("log-event-name"),
        body: {kvlistValue: {values: [denied("log-body")]}},
        attributes: (attributes("log") + [
          {key: "shell.duration_ms", value: {intValue: "12"}},
          {key: "shell.exit_code", value: {intValue: "1"}}
        ])
      }]
    }]
  }]
},
{
  resourceMetrics: [{
    resource: resource("metric"), schemaUrl: private("metric-resource-schema"),
    scopeMetrics: [{
      scope: scope("metric"), schemaUrl: private("metric-scope-schema"),
      metrics: [
        {
          name: "gen_ai.client.token.usage",
          description: private("metric-description"), unit: "{token}",
          sum: {aggregationTemporality: 2, isMonotonic: true, dataPoints: [{
            startTimeUnixNano: "1700000000000000000",
            timeUnixNano: "1700000000001000000", asInt: "42",
            attributes: attributes("datapoint"),
            exemplars: [{
              timeUnixNano: "1700000000000000000", asInt: "42",
              filteredAttributes: [denied("exemplar-attribute")]
            }]
          }]}
        },
        {
          name: private("metric-name"), unit: private("metric-unit"),
          gauge: {dataPoints: [{timeUnixNano: "1700000000001000000", asInt: "1"}]}
        }
      ]
    }]
  }]
}
