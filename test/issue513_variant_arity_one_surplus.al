## Issue #513 / spec Types §9.4 — the ONE-payload variant, surplus direction. `Pay.A(7, 8)` writes two
## values into `A(u64)`. This row exists so the rule cannot be a comparison against a fixed number:
## the expected count is read from THIS variant's own declaration, which is 1, while the very same
## enum's other variant wants 2. On the parent it built clean and ran to 7, dropping the 8.
Pay := enum { A(u64), B(u64, u64) }

main := fn() -> u64 {
  v := Pay.A(7, 8)
  match v {
    A(x) => { return x }
    B(a, b) => { return a + b }
  }
  0
}
