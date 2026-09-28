## Issue #299 — a sibling brand in the SECOND component (`F.P(7, b)` for `P(u64, A)`): `FieldDecl`
## records only the first component's type, so this one had no sink type at all. The parent ran it to 9.
A := brand(u64)
B := brand(u64)
F := enum { P(u64, A), Q }
main := fn() -> u64 {
  b : B = B(2)
  f := F.P(7, b)
  return match f { F::P(p, q) => { p + u64(q) } F::Q => { 0 } }
}
