## Issue #788 / Control Flow §5.1 — a field read through a pointer PARAMETER, `deref(p).t`. `B` is
## uncovered and no `_` default is present, so this must be refused.
C := enum { R, G, B }
H := struct { t : C }
f := fn(p : ptr(H)) -> u64 {
  match deref(p).t { R => { return 1 }; G => { return 2 } }
  return 0
}
main := fn() -> u64 {
  h := H(t = C.B)
  return f(ptr(h))
}
