## Issue #557 / Control Flow §5.1 — scrutinee shape 6 of 6: a direct CALL whose declared result is an
## enum. `B` is uncovered and no `_` default is present, so this `match` must be refused.
C := enum { R, G, B }
g := fn() -> C { return C.R }
main := fn() -> u64 {
  match g() { R => { return 1 }; G => { return 2 } }
  return 0
}
