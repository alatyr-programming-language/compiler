## Issue #557 / Control Flow §5.1 — scrutinee shape 4 of 6: `deref(p)` through a `ptr(Enum)`. This is
## the idiom the compiler itself writes (`match deref(v)`, 497 sites), and it was the shape whose
## silence made #544 stage 1 inert: a planted 25th `Expr` variant built cleanly both before and after
## the arms were enumerated. `B` is uncovered and there is no `_` default, so it must be refused.
C := enum { R, G, B }
f := fn(p : ptr(C)) -> u64 {
  match deref(p) { R => { return 1 }; G => { return 2 } }
  return 0
}
main := fn() -> u64 {
  mut c := C.R
  return f(ptr(mut c))
}
