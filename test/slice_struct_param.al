## CG-6 / Slice(T) params: a struct-element Slice(P) parameter is a pointer to the caller's
## {ptr,len} block, but indexing/iteration still must read P elements from the slice's data pointer.
P := struct { x : u64, y : u64 }

sum_idx := fn(s : Slice(P)) -> u64 {
  return s[0].x + s[1].y
}

sum_for := fn(s : Slice(P)) -> u64 {
  mut acc := 0
  for p in s {
    acc = acc + p.x + p.y
  }
  return acc
}

main := fn() -> u64 {
  ps := [P(x = 10, y = 1), P(x = 2, y = 32)]
  return sum_idx(ps[0..2]) + sum_for(ps[0..2]) - 45
}
