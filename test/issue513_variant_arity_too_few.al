## Issue #513 / spec Types §9.4 — the ticket's own form. `Pay.B(7)` writes ONE payload value into a
## variant whose declaration lists TWO positional payload types. §9.4's first bullet says the language
## "never zeroes an uninitialized binding on the programmer's behalf", so the second payload word has
## no value at all. Measured on the parent compiler this built clean on all four backends and `a + b`
## answered 7 — the missing word read as the implicit zero the specification forbids. `check` must
## refuse it instead, LOCATED at the variant name, naming the variant and the count it asks for.
Pay := enum { A(u64), B(u64, u64) }

main := fn() -> u64 {
  v := Pay.B(7)
  match v {
    A(x) => { return x }
    B(a, b) => { return a + b }
  }
  0
}
