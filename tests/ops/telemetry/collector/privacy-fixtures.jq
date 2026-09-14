# Extend the original error-status regression with synthetic content only.
def private($field): "synthetic-private-" + $field;
def attribute($key; $value): {key: $key, value: {stringValue: $value}};
def denied($field): attribute("private.content"; private($field));
def scope($signal): {
  name: ("hnet.test." + $signal),
  version: "1.2.3",
  attributes: [denied($signal + "-scope-attribute"), attribute(""; private($signal + "-empty-key"))]
};
def resource($signal): {attributes: [
  attribute("service.name"; "hnet.test"),
  attribute("originator"; "hnet-test"),
  attribute("app.version"; "password=\"synthetic-private-password with \\\"quoted\\\" spaces\""),
  denied($signal + "-resource-attribute")
]};
def attributes($signal): [
  attribute("gen_ai.operation.name"; "chat"),
  attribute("model"; "test-model-v1"),
  attribute("gen_ai.system"; "service@example.invalid"),
  attribute("app.version"; "Bearer synthetic-private-token"),
  attribute("auth_mode"; "DATABASE_PASSWORD=synthetic-private-password OPENAI_API_KEY=synthetic-private-api-key"),
  attribute("originator"; "synthetic-private-email@example.invalid"),
  attribute("session_source"; "synthetic-private-address (Unit 3)"),
  attribute("status"; "cvv=987 cvc=654"),
  attribute("error.type"; "4111 1111 1111 1111"),
  attribute("gen_ai.response.model"; "4111-1111-1111-1111"),
  {key: "gen_ai.request.model", value: {intValue: "4111111111111111"}},
  denied($signal + "-attribute")
];

.resourceSpans[0].resource = resource("trace") |
.resourceSpans[0].schemaUrl = "https://example.invalid/resource-schema" |
.resourceSpans[0].scopeSpans[0].schemaUrl = "https://example.invalid/scope-schema" |
.resourceSpans[0].scopeSpans[0].scope = scope("trace") |
.resourceSpans[0].scopeSpans[0].spans[0] |= (
  .name = private("span-name") |
  .traceState = "test=span" |
  .attributes = attributes("span") + [
    {key: "gen_ai.usage.input_tokens", value: {intValue: "42"}}
  ] |
  .events = [{
    timeUnixNano: "1700000000000000000", name: private("event-name"),
    attributes: attributes("event")
  }] |
  .links = [{
    traceId: "00000000000000000000000000000002", spanId: "0000000000000002",
    traceState: "test=linked",
    attributes: [attribute("link.type"; "retry")]
  }]
),
{
  resourceLogs: [{
    resource: resource("log"), schemaUrl: "https://example.invalid/resource-schema",
    scopeLogs: [{
      scope: scope("log"), schemaUrl: "https://example.invalid/scope-schema",
      logRecords: [{
        timeUnixNano: "1700000000000000000",
        observedTimeUnixNano: "1700000000001000000",
        severityNumber: 17, severityText: "ERROR",
        eventName: "hnet.test.diagnostic",
        body: {kvlistValue: {values: [denied("log-body")]}},
        attributes: (attributes("log") + [
          {key: "shell.duration_ms", value: {intValue: "12"}},
          {key: "shell.exit_code", value: {intValue: "1"}}
        ])
      }, {
        timeUnixNano: "1700000000000000000",
        eventName: "codex.api_request", severityText: "ERROR"
      }]
    }]
  }]
},
{
  resourceMetrics: [{
    resource: resource("metric"), schemaUrl: "https://example.invalid/resource-schema",
    scopeMetrics: [{
      scope: scope("metric"), schemaUrl: "https://example.invalid/scope-schema",
      metrics: [
        {
          name: "gen_ai.client.token.usage",
          description: "Tokens used", unit: "{token}",
          metadata: [attribute("source"; "test")],
          sum: {aggregationTemporality: 2, isMonotonic: true, dataPoints: [{
            startTimeUnixNano: "1700000000000000000",
            timeUnixNano: "1700000000001000000", asInt: "42",
            attributes: attributes("datapoint"),
            exemplars: [{
              timeUnixNano: "1700000000000000000", asInt: "42",
              filteredAttributes: [attribute("sample"; "test")]
            }]
          }]}
        },
        {
          name: "hnet.test.operations", unit: "{operation}",
          gauge: {dataPoints: [{timeUnixNano: "1700000000001000000", asInt: "1"}]}
        }
      ]
    }]
  }]
}
