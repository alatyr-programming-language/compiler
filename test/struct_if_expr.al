## e2e (struct-valued if-EXPRESSION whose branches are CALLS). The if-expr value type is a
## multi-word struct; each branch is a call returning P. Binding `x :=` must deliver the struct
## (was silent 0 — an if-expr converged its value as a scalar rax, dropping the sret struct).
## test(1) -> f() -> P(v=42) -> x.v = 42.
P := struct { v : u64 }
f := fn() -> P { return P(v = 42) }
g := fn() -> P { return P(v = 7) }
main := fn() -> u64 {
  c := u64(1)
  x := if c > 0 { f() } else { g() }
  return x.v
}
