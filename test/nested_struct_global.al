## e2e — a NESTED-aggregate mutable global (`mut O := Outer(p = Inner(...), q = ...)`, a struct with a
## struct field). The .data cells are emitted RECURSIVELY by field (a nested struct field is one arg but
## several words — the old word-count loop overran the arg list and crashed the compiler). O flattens to
## [a=30, b=2, q=10]; `s := O` snapshots them, `s.p.a + s.p.b + s.q` = 30 + 2 + 10 = 42.
Inner := struct { a : u64, b : u64 }
Outer := struct { p : Inner, q : u64 }
mut O := Outer(p = Inner(a = 30, b = 2), q = 10)
main := fn() -> u64 {
  s := O
  s.p.a + s.p.b + s.q
}
