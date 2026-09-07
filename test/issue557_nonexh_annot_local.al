## Issue #557 / Control Flow §5.1 — scrutinee shape 2 of 6: an ANNOTATED LOCAL binding. `B` is
## uncovered and no `_` default is present, so this `match` must be refused.
C := enum { R, G, B }
main := fn() -> u64 {
  c : C = C.R
  match c { R => { return 1 }; G => { return 2 } }
  return 0
}
