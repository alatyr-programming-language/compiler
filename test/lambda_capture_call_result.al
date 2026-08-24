## FN-6 CAPTURE of an AGGREGATE returned by a call — `p := mk(40)` has no explicit `: P`
## annotation, so the lift must recover P from `mk`'s declared return type and append `p` as a typed
## by-ref capture param. `p.x + p.y` = 42.
P := struct { x : u64, y : u64 }

mk := fn(a : u64) -> P {
  return P(x = a, y = 2)
}

main := fn() -> u64 {
  p := mk(40)
  f := fn(n : u64) -> u64 { return n + p.x + p.y }
  return f(0)
}
