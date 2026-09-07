## Issue #513 / spec Types §9.4 — the REVERSE direction the ticket asked to measure rather than
## assume: a surplus payload value. `Pay.B(7, 8, 9)` writes THREE values into a two-payload variant.
## On the parent this also built clean and ran to 15 (7 + 8), the third value silently dropped — a
## constructor that quietly ignores an argument the author wrote. The same one-sided arity rule
## refuses both directions, so this row is what proves the check is not a lower bound.
Pay := enum { A(u64), B(u64, u64) }

main := fn() -> u64 {
  v := Pay.B(7, 8, 9)
  match v {
    A(x) => { return x }
    B(a, b) => { return a + b }
  }
  0
}
