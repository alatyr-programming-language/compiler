## CG-6 / Slice(T) params: passing a named local struct-element slice view must pass the
## local {ptr,len} block, not the slice's data pointer.
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
  s := ps[0..2]
  return sum_idx(s) + sum_for(s) - 45
}
