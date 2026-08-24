## CT-6/TYP-9: a concrete ordinary struct can project each Field descriptor in a comptime-for.
## The projection is erased to the same scalar field read as `v.x`/`v.y`; no runtime field lookup
## or RTTI is involved. This deliberately exercises the non-generic emitter path.
S := struct { x : u64, y : u64 }

sum_fields := fn(v : S) -> u64 {
  mut total : u64 = 0
  comptime for f in typeinfo(S).fields { total = total + v.(f) }
  total
}

main := fn() -> u64 { sum_fields(S(x = 40, y = 2)) }
