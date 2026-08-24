## Probe: the ordinary scalar Field projection `v.(f)` is supported by the
## typeinfo derive path. A capability query over the same expression must see
## the same type without evaluating `v`.
S := struct { x : u64, y : u64 }

takes_u := fn(x : u64) -> u64 { x }
takes_str := fn(x : str) -> u64 { 0 }

sum_projection := fn(v : S) -> u64 {
mut total : u64 = 0
comptime for f in typeinfo(S).fields { total = total + takes_u(v.(f)) }
total
}

main := fn() -> u64 {
v := S(x = 40, y = 2)
mut query_hits : u64 = 0
comptime for f in typeinfo(S).fields {
  if compiles(takes_u(v.(f))) { query_hits += 1 }
  if compiles(takes_str(v.(f))) { query_hits += 100 }
}
if sum_projection(v) == 42 and query_hits == 2 { 42 } else { 1 }
}
