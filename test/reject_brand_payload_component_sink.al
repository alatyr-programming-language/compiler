## Issue #299 — a SIBLING brand in the FIRST component of a two-component variant payload
## (`F.P(b, 7)` for `P(A, u64)`). The parent judged only arity-1 payloads and ran this to 9. Refused now.
A := brand(u64)
B := brand(u64)
F := enum { P(A, u64), Q }
main := fn() -> u64 {
  b : B = B(2)
  f := F.P(b, 7)
  return match f { F::P(p, q) => { u64(p) + q } F::Q => { 0 } }
}
