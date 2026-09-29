## Issue #299 — the over-rejection control for the per-component payload sink: three components, the
## last a generic `Option(u64)`, every one legal. 30 + 12 = 42.
A := brand(u64)
F := enum { P(A, u64, Option(u64)), Q }
main := fn() -> u64 {
  f := F.P(A(30), 12, Option(u64).None)
  return match f { F::P(p, q, o) => { u64(p) + q } F::Q => { 0 } }
}
