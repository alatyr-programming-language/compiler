## Issue #680 / Control Flow §5.1 — shape 6 of 6: the pointer IS annotated, the value local bound from
## its `deref` is not. Found while measuring #680: an annotation on the pointer did not reach a value
## read through it, so this spelling was unchecked too. `B` is uncovered.
C := enum { R, G, B }
g := fn(k : u64) -> C {
  if k == 0 { return C.R }
  return C.G
}
gp := fn(p : ptr(mut C)) -> ptr(mut C) { p }
main := fn() -> u64 {
  mut c := C.R
  p : ptr(mut C) = gp(ptr(mut c))
  x := deref(p)
  match x { R => { return 42 }; G => { return 1 } }
  return 2
}
