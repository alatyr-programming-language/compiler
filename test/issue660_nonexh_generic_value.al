## Issue #660 / Control Flow §5.1 — a GENERIC call whose result is `T` by value (`c := pass(C, C.R)`):
## the value's type is the type argument. Accepted by the parent with `B` uncovered; refused now.
C := enum { R, G, B }
pass := fn(T : type, v : T) -> T { v }
main := fn() -> u64 {
  c := pass(C, C.R)
  match c { R => { return 42 }; G => { return 1 } }
  return 2
}
