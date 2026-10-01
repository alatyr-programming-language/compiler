## Issue #790 — a whole multi-word enum copied through pointers. On the parent each copy below built
## cleanly and copied neither the tag nor the payload (without the last check this program exited 2,
## the first check, where 42 was due; the last check made the parent refuse the build, since the
## binding was not an enum at all): `deref(dst) = deref(src)` in a helper, the same between two values of one
## variant, the same through annotated `ptr` locals, and through a local bound from the pointee
## (`v : E = deref(src)`, which took one scalar word, so the later store moved the tag alone). An
## inferred `w := deref(src)` read back and matched is the binding on its own. Each check has its own
## exit code.
E := enum { Num(u64), Var(u64, u64), Pair(u64, u64, u64) }
cp := fn(dst : ptr(mut E), src : ptr(E)) { deref(dst) = deref(src) }
cp_via := fn(dst : ptr(mut E), src : ptr(E)) {
  v : E = deref(src)
  deref(dst) = v
}
rd := fn(p : ptr(E)) -> u64 {
  match deref(p) { E::Num(x) => { 1 } E::Var(s, n) => { s + n } E::Pair(x, y, z) => { 3 } }
}
main := fn() -> u64 {
  b : E = E.Var(30, 12)
  mut a1 : E = E.Num(1)
  cp(ptr(mut a1), ptr(b))
  if rd(ptr(a1)) != 42 { return 2 }
  mut a2 : E = E.Var(1, 1)
  cp(ptr(mut a2), ptr(b))
  if rd(ptr(a2)) != 42 { return 3 }
  mut a3 : E = E.Num(1)
  dp : ptr(mut E) = ptr(mut a3)
  sp : ptr(E) = ptr(b)
  deref(dp) = deref(sp)
  if rd(ptr(a3)) != 42 { return 4 }
  mut a4 : E = E.Pair(1, 2, 3)
  cp_via(ptr(mut a4), ptr(b))
  if rd(ptr(a4)) != 42 { return 5 }
  w := deref(sp)
  match w { E::Num(x) => { return 6 } E::Var(s, n) => { if s + n != 42 { return 7 } } E::Pair(x, y, z) => { return 8 } }
  42
}
