def id: "client_" + (.port | tostring);
def auth: "bearertokenauth/" + id;
def receiver: "otlp/" + id;
def host: "resource/" + id;

{
  extensions: (map({key: auth, value: {tokens: ["${env:" + .tokenEnv + "}"]}}) | from_entries),
  receivers: (map({key: receiver, value: {protocols: {http: {
    endpoint: ("0.0.0.0:" + (.port | tostring)), auth: {authenticator: auth}
  }}}}) | from_entries),
  processors: (map({key: host, value: {attributes: [{
    key: "host.name", action: "upsert", value: .name
  }]}}) | from_entries),
  service: {
    extensions: (["file_storage", "health_check"] + map(auth)),
    pipelines: ([.[] as $client | ["logs", "metrics", "traces"][] as $signal | {
      key: ($signal + "/" + ($client | id)),
      value: {
        receivers: [($client | receiver)],
        processors: ["memory_limiter", "transform/privacy", "redaction/sensitive", ($client | host), "resource/pipeline"],
        exporters: ["clickhouse"]
      }
    }] | from_entries)
  }
}
