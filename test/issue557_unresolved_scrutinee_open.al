## Issue #557 / Control Flow §5.1 — the FAIL-OPEN control. Where the scrutinee's type genuinely does
## not resolve, skipping the exhaustiveness decision is still correct; the defect this issue fixed was
## that skipping had become the NORMAL case, not that it exists. An UNANNOTATED local bound from a
## CALL is the deliberate exclusion: `check_stmts` adopts a callee's declared return type for a
## struct only, because adopting a generic enum return (`Result(U, E)`) would make the variant lookup
## mis-resolve and spuriously reject. So `c := g(0)` records no enum type and the non-exhaustive
## `match c` below is accepted, while the same call used DIRECTLY as the scrutinee (`match g(0)`) is
## refused — see issue557_nonexh_call. That asymmetry is #557's measured residual, not a decision that
## the shape may stay unchecked. It takes the covered arm and answers 42 on all four backends.
C := enum { R, G, B }
g := fn(k : u64) -> C {
  if k == 0 { return C.R }
  return C.G
}
main := fn() -> u64 {
  c := g(0)
  match c { R => { return 42 }; G => { return 1 } }
  return 2
}
