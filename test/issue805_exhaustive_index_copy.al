## Issue #805 / Control Flow §5.1 — the over-rejection control for the copied array: `match ys[0]`
## over `ys := xs` naming every variant is exhaustive and `check` accepts it. (`build` refuses this
## spelling for a lowering reason, "indexing a SCALAR local"; the checker's verdict is the property
## under test here.)
C := enum { R, G, B }
main := fn() -> u64 {
  xs : [C; 2] = [C.B, C.G]
  ys := xs
  r := match ys[0] { R => { 11 }; G => { 22 }; B => { 42 } }
  return r
}
