## Issue #513 / spec Types §9.4 — the ONE-payload variant, empty direction. `Pay.A()` writes NO value
## into `A(u64)`, so the single payload word has no value under §9.4. On the parent this built clean
## and ran to 0 — the worst reading of the three, because 0 is also a perfectly plausible answer, so
## nothing about the run says the value was never written. The pair with the surplus row above is what
## pins the expected count to this variant's declaration rather than to the widest variant's.
Pay := enum { A(u64), B(u64, u64) }

main := fn() -> u64 {
  v := Pay.A()
  match v {
    A(x) => { return x }
    B(a, b) => { return a + b }
  }
  0
}
