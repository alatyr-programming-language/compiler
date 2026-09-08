## Issue #557 / Control Flow §5.1 — a `match` MUST be exhaustive; a non-exhaustive one is a compile
## error. Scrutinee shape 1 of 6: a BY-VALUE PARAMETER. Exhaustiveness is a property of the
## scrutinee's TYPE, not of how the scrutinee is spelled, so each of the six spellings the checker can
## meet has its own fixture. `B` is uncovered and no `_` default is present, so this must be refused.
C := enum { R, G, B }
f := fn(c : C) -> u64 {
  match c { R => { return 1 }; G => { return 2 } }
  return 0
}
main := fn() -> u64 { return f(C.R) }
