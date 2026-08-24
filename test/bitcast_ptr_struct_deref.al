## Aggregate deref through a BITCAST-DERIVED struct pointer (no type annotation).
## `vp := unchecked bitcast(ptr(Point), addr)` must infer ek=7 (pointer-to-struct) so a
## following `deref(vp)` / `vp.f` resolves the aggregate through the pointer instead of
## reading zeros. Returns 42.
Point := struct { x : i64, y : i64 }

main := fn() -> u64 {
  mut q := Point(x = 12, y = 30)
  bi := unchecked bitcast(usize, ptr(q))
  vp := unchecked bitcast(ptr(Point), bi)   ## bitcast-derived struct ptr, INFERRED ek=7

  ## whole-struct copy through the bitcast ptr
  p := deref(vp)
  s1 := u64(p.x + p.y)                       ## 12 + 30 = 42

  ## field write-then-read through the bitcast ptr
  vp.x = 100
  s2 := u64(vp.x + vp.y)                      ## 100 + 30 = 130

  if s1 == 42 and s2 == 130 { u64(42) } else { u64(0) }
}
