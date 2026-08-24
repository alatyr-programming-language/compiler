## e2e — a TUPLE with a MULTI-WORD (aggregate) component `(Pt, u64)` constructs + indexes correctly.
## The tuple literal `(Pt(…), 12)` places the struct component's words THEN the scalar at a cumulative
## offset (the old homogeneous construction emitted the scalar via the struct path and dropped it, so
## `t.1` read uninitialised → 0). `t.0.x`/`t.0.y` read the struct component's fields, `t.1` the scalar.
## Returns 42 = 10 + 20 + 12.
Pt := struct { x : u64, y : u64 }

main := fn() -> u64 {
  t : (Pt, u64) = (Pt(x = 10, y = 20), 12)
  t.0.x + t.0.y + t.1
}
