## QUERY/CT-6: capability queries may consume aggregate-valued `v.(f)` without
## entering ordinary value-position emission. Each sink must match only its field type.
Pair := struct { x : u64, y : u64 }
Holder := struct { pair : Pair, text : str, nums : [u64; 2], coords : (u64, u64), scalar : u64 }

takes_pair := fn(v : Pair) -> u64 { v.x + v.y }
takes_str := fn(v : str) -> u64 { v.len() }
takes_array := fn(v : [u64; 2]) -> u64 { v[0] + v[1] }
takes_tuple := fn(v : (u64, u64)) -> u64 { v.0 + v.1 }
takes_scalar := fn(v : u64) -> u64 { v }

main := fn() -> u64 {
mut pair_hits : u64 = 0
mut str_hits : u64 = 0
mut array_hits : u64 = 0
mut tuple_hits : u64 = 0
mut scalar_hits : u64 = 0
v := Holder(pair = Pair(x = 40, y = 2), text = "ok", nums = [1, 2], coords = (3, 4), scalar = 5)
comptime for f in typeinfo(Holder).fields {
  if compiles(takes_pair(v.(f))) { pair_hits += 1 }
  if compiles(takes_str(v.(f))) { str_hits += 1 }
  if compiles(takes_array(v.(f))) { array_hits += 1 }
  if compiles(takes_tuple(v.(f))) { tuple_hits += 1 }
  if compiles(takes_scalar(v.(f))) { scalar_hits += 1 }
}
if pair_hits == 1 and str_hits == 1 and array_hits == 1 and tuple_hits == 1 and scalar_hits == 1 { 42 } else { 1 }
}
