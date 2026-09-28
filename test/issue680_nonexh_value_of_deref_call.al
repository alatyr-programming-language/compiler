## Issue #680 / Control Flow §5.1 — shape 4 of 6: an unannotated VALUE local bound from `deref` of a
## call (`x := deref(gp(…))`, the `x := deref(stmt_p(Stmt, st))` spelling with a non-generic callee).
## `B` is uncovered.
C := enum { R, G, B }
g := fn(k : u64) -> C {
  if k == 0 { return C.R }
  return C.G
}
gp := fn(p : ptr(mut C)) -> ptr(mut C) { p }
main := fn() -> u64 {
  mut c := C.R
  x := deref(gp(ptr(mut c)))
  match x { R => { return 42 }; G => { return 1 } }
  return 2
}
