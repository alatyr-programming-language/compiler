## Types §4.6 / TYP-6 — a user `@convert` whose TARGET is a BUILTIN-conv scalar name (`u64`) and whose
## OPERAND is a TUPLE. `u64(t)` is NOT the scalar lattice (a tuple is an N-word aggregate, not a lattice
## scalar), so it must dispatch to the single in-scope `@convert fn((i64,i64)) -> u64`. Before the
## aggregate-operand guard covered tuples, this silently read the tuple's WORD 0 (`40`); now it routes
## to the @convert. Returns 42.
tu := @convert fn(t : (i64, i64)) -> u64 { return 42 }
main := fn() -> u64 {
  t := (40, 2)
  return u64(t)
}
