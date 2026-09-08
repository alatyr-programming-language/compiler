## Issue #557 / Control Flow §5.1 + §5.2 — the NEGATIVE half of the OR-pattern control: grouping is
## sugar, not a wildcard. Dropping `D` from the second group leaves a variant uncovered with no `_`
## default, so the `match` must be refused — through the `deref(p)` scrutinee, the shape the compiler
## itself writes and the one that used to skip the check entirely.
E := enum { A, B, C, D }
f := fn(p : ptr(E)) -> u64 {
  match deref(p) { A | B => { return 1 }; C => { return 2 } }
  return 0
}
main := fn() -> u64 {
  mut v := E.A
  return f(ptr(mut v))
}
