## Issue #680 / Control Flow §5.1 — shape 1 of 6: an UNANNOTATED local bound from a CALL whose declared
## result is an enum (`c := g(0)`). Until #680 the binding recorded no enum type, so the `match` below
## skipped the exhaustiveness check, built, and took the `R` arm; it was kept in the tree as #557's
## fail-open residual. `B` is uncovered and there is no `_` default, so it must be refused.
C := enum { R, G, B }
g := fn(k : u64) -> C {
  if k == 0 { return C.R }
  return C.G
}
gp := fn(p : ptr(mut C)) -> ptr(mut C) { p }
main := fn() -> u64 {
  c := g(0)
  match c { R => { return 42 }; G => { return 1 } }
  return 2
}
