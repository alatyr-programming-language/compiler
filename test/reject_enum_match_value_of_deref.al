## Issue #716 — the same enum read through `v := deref(ptr(mut x))` into a value local first. The parent
## built it and ran to 1 (no arm taken for `B`). Refused now.
C := enum { R, G, B }
main := fn() -> u64 {
  mut x := C.B
  v := deref(ptr(mut x))
  match v { R => { return 10 }; G => { return 20 }; B => { return 42 } }
  return 1
}
