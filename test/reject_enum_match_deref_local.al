## Issue #716 — a `match` over `deref` of a pointer to an enum LOCAL of the same function. The x86_64
## lowering could not see the scrutinee's enum type and compared every arm against tag 0: on the parent
## this built and ran to 1 — the `G` value took no arm. It is now a located refusal.
C := enum { R, G, B }
main := fn() -> u64 {
  mut x := C.G
  match deref(ptr(mut x)) { R => { return 10 }; G => { return 42 }; B => { return 30 } }
  return 1
}
