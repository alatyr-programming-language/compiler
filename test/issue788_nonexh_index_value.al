## Issue #788 / Control Flow §5.1 — the array-element scrutinee in VALUE position. With `xs[0] = C.B`
## no arm covers the value; the parent built it and bound `r` to 0, a silent wrong value.
C := enum { R, G, B }
main := fn() -> u64 {
  xs : [C; 2] = [C.B, C.G]
  r := match xs[0] { R => { 11 }; G => { 22 } }
  return r
}
