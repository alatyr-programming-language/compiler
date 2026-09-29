## Issue #716 — `match deref(q)` over an ANNOTATED pointer-to-enum LOCAL (`q : ptr(C) = p`). The
## lowering typed only a `p : ptr(C)` PARAMETER, so this scrutinee reached the integer path and every
## arm compared with 0 (returning `R`'s 10 for any variant, or falling through for a non-zero one);
## that path now refuses. The local is bound like the parameter and dispatches on `C`'s
## discriminant: `G` is variant 1, so only a real dispatch returns 42.
C := enum { R, G, B }
f := fn(p : ptr(mut C)) -> u64 {
  q : ptr(C) = p
  match deref(q) { R => { return 10 }; G => { return 42 }; B => { return 30 } }
  return 1
}
main := fn() -> u64 {
  mut x := C.G
  f(ptr(mut x))
}
