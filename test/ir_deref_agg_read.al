## e2e — #1723: `deref(p)` read WHOLE on the shared IR. In value context `deref(p)` loads the pointee
## (Memory §4.3), and an aggregate pointee is a value of its own: the builder copies it out of the
## address into a fresh frame object, exactly as it reads a by-reference parameter. The pointee type is
## the one the operand's declaration spells: here, a pointer name declared `ptr(T)` (the call declared
## `-> ptr(T)` is in `test/ir_deref_agg_call.al`). A struct must be WORD tier, the only struct a place
## through a pointer may be (`docs/ir.md` §3.7). An enum is taken in the one shared layout.
##   * `v : S = deref(p)` and `w := deref(p)`: a COPY, so a later write through `p` leaves them as read;
##   * `match deref(q)` over an enum pointee, one variant per check;
##   * `deref(pp)` of a `ptr(Option(ptr(u64)))`: the one folded word (#1337's shape).
## Each check answers its own code when it fails; 42 when all held.
S := struct { a : u64, b : u64 }
E := enum { A, B(u64), C(u64, u64) }

tag := fn(q : ptr(E)) -> u64 {
  match deref(q) { E.A => { return 1 }; E.B(x) => { return x }; E.C(x, y) => { return x * 10 + y } }
}
copy_then_write := fn(p : ptr(mut S)) -> u64 {
  v : S = deref(p)
  w := deref(p)
  p.a = 90
  deref(p).b = 80
  v.a + v.b + w.a + w.b
}
folded := fn(pp : ptr(Option(ptr(u64)))) -> u64 {
  o : Option(ptr(u64)) = deref(pp)
  match o { Some(r) => { return deref(r) }; None => { return 7 } }
}

main := fn() -> u64 {
  mut s := S(a = 3, b = 4)
  if copy_then_write(ptr(mut s)) != 14 or s.a != 90 or s.b != 80 { return 1 }
  mut e := E.A
  if tag(ptr(e)) != 1 { return 2 }
  e = E.B(9)
  if tag(ptr(e)) != 9 { return 3 }
  e = E.C(3, 4)
  if tag(ptr(e)) != 34 { return 4 }
  mut x : u64 = 35
  mut o : Option(ptr(u64)) = Option(ptr(u64)).Some(ptr(x))
  mut n : u64 = folded(ptr(o))
  o = Option(ptr(u64)).None
  n = n + folded(ptr(o))
  if n != 42 { return 5 }
  return 42
}
## expect: run 42
