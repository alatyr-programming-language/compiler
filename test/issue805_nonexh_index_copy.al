## Issue #805 / Control Flow §5.1 — an element of a COPIED array, `ys := xs` over `[C; 2]`. `B` is
## uncovered and no `_` default is present, so this must be refused; the parent's `check` passed it.
C := enum { R, G, B }
main := fn() -> u64 {
  xs : [C; 2] = [C.B, C.G]
  ys := xs
  r := match ys[0] { R => { 11 }; G => { 22 } }
  return r
}
