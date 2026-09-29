## Issue #716 — the control: the spelling the refusal's diagnostic recommends, `match deref(p)` over an
## annotated pointer PARAMETER, which the lowering types. Every variant reaches its own arm on the
## parent and here: 10 + 20 + 12 = 42.
C := enum { R, G, B }
val := fn(p : ptr(C)) -> u64 {
  match deref(p) { R => { return 10 }; G => { return 20 }; B => { return 12 } }
  return 0
}
main := fn() -> u64 {
  mut r := C.R
  mut g := C.G
  mut b := C.B
  return val(ptr(mut r)) + val(ptr(mut g)) + val(ptr(mut b))
}
