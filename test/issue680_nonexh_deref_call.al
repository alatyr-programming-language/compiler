## Issue #680 / Control Flow §5.1 — shape 3 of 6: the call INLINED into the scrutinee,
## `match deref(gp(…))`. The `deref` branch of the scrutinee resolver answered only for a pointer
## LOCAL, so inlining the call did not help either. `B` is uncovered.
C := enum { R, G, B }
g := fn(k : u64) -> C {
  if k == 0 { return C.R }
  return C.G
}
gp := fn(p : ptr(mut C)) -> ptr(mut C) { p }
main := fn() -> u64 {
  mut c := C.R
  match deref(gp(ptr(mut c))) { R => { return 42 }; G => { return 1 } }
  return 2
}
