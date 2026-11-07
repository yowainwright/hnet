def snapshot_epoch:
  [capture("^(?<date>[0-9-]+T[0-9:]+)(?:[.][0-9]+)?(?<zone>Z|[+-][0-9]{2}:[0-9]{2})$")]
  | if length == 1 then .[0] else error("Invalid snapshot time") end
  | . as $t
  | ($t.date + "Z" | fromdateiso8601) as $base
  | if $t.zone == "Z" then $base
    else ((($t.zone[1:3] | tonumber) * 3600) + (($t.zone[4:6] | tonumber) * 60)) as $offset
      | $base - (if $t.zone[0:1] == "+" then $offset else -$offset end)
    end;

if type != "array" then error("Snapshot listing must be an array") else . end
| map(select((.tags // []) | index("agent-telemetry")))
| map(if (.id | test("^[0-9a-f]{64}$")) then . else error("Invalid snapshot ID") end)
| map(select((.time | snapshot_epoch) < ($now - $days * 86400)))
| map(.id)
