## Issue #299 — a brand over ANOTHER block in a component declared plain `u64` (`F.P(A(1), c)` for
## `c : C`, `C := brand(u8)`) — the B1R direction, through component 2. The parent ran it to 4.
A := brand(u64)
C := brand(u8)
F := enum { P(A, u64), Q }
main := fn() -> u64 {
  c : C = C(3)
  f := F.P(A(1), c)
  return match f { F::P(p, q) => { u64(p) + q } F::Q => { 0 } }
}
