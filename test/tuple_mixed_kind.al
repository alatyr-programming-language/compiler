## §4/§8: a MIXED-KIND tuple LOCAL — a scalar component followed by a wider struct component. Element N
## now uses its OWN type + cumulative offset (via the per-component layout table), not the uniform
## first-component type, so t.1.x/.y read the right words. Was a silent miscompile (returned 36).
## t.0 + t.1.x + t.1.y = 12 + 20 + 10 = 42.
Pt := struct { x : u64, y : u64 }

main := fn() -> u64 {
  t := (12, Pt(x = 20, y = 10))
  return t.0 + t.1.x + t.1.y
}
