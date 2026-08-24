## e2e/fmt — `Expr::Bitcast` carries a type span, and the parser fills that span from THREE different
## surfaces (`p_factor`'s bitcast branch): the POINTEE name of a sub-word `ptr(u8)` (span `u8`), the
## WHOLE pointer type of `ptr(mut S)` (span `ptr(mut S)`), and the bare TARGET TYPE of an
## aggregate→aggregate reinterpret `bitcast(B, x)` (span `B`). fmt used to decide by "does the span
## start with `ptr(`" and put `ptr(…)` round everything that did not — conflating the aggregate target
## with a sub-word pointee, so `y := bitcast(B, x)` came back `y := unchecked bitcast(ptr(B), x)`: a
## POINTER where a struct value stood. `bitcast_agg2word` ran 42 before a reformat and SEGFAULTED
## after. The parser's own gate (a bare pointee is preserved only when it is a SUB-WORD SCALAR) is
## what fmt now mirrors.
##
## The `unchecked` marker is recovered too, and NOT invented: the node records nothing about it, and
## `unchecked bitcast(B, x)` over a 2-word aggregate is a DIFFERENT program from the plain form today
## (it yields 0 where the plain form yields 42 — a lower bug in its own right), so an added marker was
## itself a silent miscompile.
## The three shapes below, in order: `y` is aggregate -> aggregate with the target written BARE and
## no `unchecked` marker; `sp` is a POINTER-to-user-type target whose whole `ptr(mut S)` is the span
## and must come back verbatim; `bp` is a SUB-WORD pointee whose span is the bare `u8`, so the
## `ptr(…)` around it has to be put back.
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
