## Issue #788 / Control Flow §5.1 — a field read THROUGH an address-of, `deref(ptr(h)).t`, whose
## declared type is an enum. `B` is uncovered and no `_` default is present. The parent's `check`
## passed it while `build` refused it for a lowering reason (#716); both must now refuse it.
C := enum { R, G, B }
H := struct { t : C }
main := fn() -> u64 {
  h := H(t = C.R)
  match deref(ptr(h)).t { R => { return 1 }; G => { return 2 } }
  return 0
}
