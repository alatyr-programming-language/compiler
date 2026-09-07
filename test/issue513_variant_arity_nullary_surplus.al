## Issue #513 / spec Types §9.4 — the ZERO-payload variant given a value. `E.N(5)` supplies one value
## to a variant whose declaration carries no payload list at all. On the parent it built clean and ran
## to 9 (the N arm), the 5 dropped without a word. This is the lower end of the same rule: the count a
## variant asks for may be zero, and the constructor still has to match it.
E := enum { N, A(u64) }

main := fn() -> u64 {
  v := E.N(5)
  match v {
    N => { return 9 }
    A(x) => { return x }
  }
  0
}
