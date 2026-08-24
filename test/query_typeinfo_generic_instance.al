## P1-QUERY/CT-6: a generic instance must substitute T before checking a
## capability query that consumes the active `typeinfo(T).fields` projection.
Pair := struct { x : u64, y : u64 }
Mixed := struct { scalar : u64, pair : Pair, text : str }

takes_u64 := fn(v : u64) -> u64 { v }
takes_pair := fn(v : Pair) -> u64 { v.x + v.y }
takes_str := fn(v : str) -> u64 { v.len() }

query_fields := fn(T : type, v : T) -> u64 {
  mut scalar_hits : u64 = 0
  mut pair_hits : u64 = 0
  mut text_hits : u64 = 0
  comptime for f in typeinfo(T).fields {
    if compiles(takes_u64(v.(f))) { scalar_hits += 1 }
    if compiles(takes_pair(v.(f))) { pair_hits += 1 }
    if compiles(takes_str(v.(f))) { text_hits += 1 }
  }
  if scalar_hits == 1 and pair_hits == 1 and text_hits == 1 { 42 } else { 1 }
}

main := fn() -> u64 {
  v := Mixed(scalar = 40, pair = Pair(x = 1, y = 2), text = "ignored")
  query_fields(Mixed, v)
}
