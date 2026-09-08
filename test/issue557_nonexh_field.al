## Issue #557 / Control Flow §5.1 — scrutinee shape 5 of 6: a struct FIELD read whose declared type is
## an enum. `B` is uncovered and no `_` default is present, so this `match` must be refused.
C := enum { R, G, B }
H := struct { t : C }
main := fn() -> u64 {
  h := H(t = C.R)
  match h.t { R => { return 1 }; G => { return 2 } }
  return 0
}
