## Issue #680 / Control Flow §5.1 — shape 5 of 6: an unannotated value local bound from `deref` of an
## unannotated pointer local that was itself bound from a call. Rebinding through a second local did not
## recover the type (the issue's row c). `B` is uncovered.
C := enum { R, G, B }
g := fn(k : u64) -> C {
  if k == 0 { return C.R }
  return C.G
}
gp := fn(p : ptr(mut C)) -> ptr(mut C) { p }
main := fn() -> u64 {
  mut c := C.R
  p := gp(ptr(mut c))
  x := deref(p)
  match x { R => { return 42 }; G => { return 1 } }
  return 2
}
