## e2e/fmt — `Expr::Bitcast` carries a complete target span for THREE representation-significant
## surfaces (`p_factor`'s bitcast branch): a sub-word pointer target `ptr(u8)`, a pointer target such
## as `ptr(mut S)`, and the bare TARGET TYPE of an aggregate→aggregate reinterpret `bitcast(B, x)`.
## fmt emits the stored target verbatim, so it cannot conflate a pointer target with an aggregate value
## target or lose pointer mutability. A bare word-sized scalar target remains identity-erased.
##
## The `unchecked` marker is recovered too, and NOT invented: the node records nothing about it, and
## `unchecked bitcast(B, x)` over a 2-word aggregate is a DIFFERENT program from the plain form today
## (it yields 0 where the plain form yields 42 — a lower bug in its own right), so an added marker was
## itself a silent miscompile.
## The three shapes below, in order: `y` is aggregate -> aggregate with the target written BARE and
## no `unchecked` marker; `sp` is a POINTER-to-user-type target whose whole `ptr(mut S)` is the span
## and must come back verbatim; `bp` is a SUB-WORD pointer target whose complete `ptr(u8)` span also
## comes back verbatim.
A := struct { a : u64, b : u64 }
B := struct { p : u64, q : u64 }
S := struct { m : u64 }

main := fn() -> u64 {
  x := A(a = 40, b = 2)
  y := bitcast(B, x)
  if y.p + y.q != 42 { return 1 }

  mut s := S(m = 7)
  addr := unchecked bitcast(usize, ptr(mut s))
  sp := unchecked bitcast(ptr(mut S), addr)
  if deref(sp).m != 7 { return 2 }

  bp := unchecked bitcast(ptr(u8), addr)
  if u64(deref(bp)) != 7 { return 3 }

  return 42
}
