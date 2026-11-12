## e2e — #1026 (IR coverage, #980 step 3): an `in out` / `out` STRUCT parameter is built by the shared IR.
## Functions §2.1: an `out` / `in out` parameter denotes the CALLER's place; §2.3: it is bound by a
## mutable place argument, read and written in place; §4.1: passed by reference to that place. The IR
## builder refused every such function ("parameter with a mode") and every call to one, so the twins took
## their legacy emitters for all of them. MEASURED on the parent: x86_64 answered 42, aarch64 133,
## riscv64 133 and wasm 134 (traps). Covered: field writes through the parameter, the parameter passed on
## to another `in out` (`twice`), a field of a struct local as the place (`o.inner`), an `out` written
## field by field (`fill`), a place through a pointer (`deref(q)`), an `in out` enum read in place
## (`weight`), and both mixes with a function the
## builder still refuses (a float literal): an IR caller of it, and it calling IR callees.
## expect: run 42
P := struct { x : u64, y : u64 }
O := struct { tag : u64, inner : P }

bump := fn(in out p : P, by : u64) {
  p.x = p.x + by
  p.y = p.y + 1
}
twice := fn(in out p : P) {
  bump(p, 2)
  bump(p, 3)
}
fill := fn(out r : P) {
  r.x = 4
  r.y = 5
}
legacy_bump := fn(in out p : P) {
  f : f64 = 1.5
  if f > 1.0 { p.x = p.x + 10 }
}
legacy_caller := fn() -> u64 {
  g : f64 = 2.5
  mut w := P(x = 1, y = 1)
  if g > 1.0 { bump(w, 1) }   ## w = {2, 2}
  twice(w)                    ## w = {7, 4}
  w.x + w.y                   ## 11
}
via_ptr := fn(q : ptr(mut P)) {
  bump(deref(q), 1)
}
## an `in out` ENUM parameter, read in place
E := enum { A(u64), B(u64, u64) }
weight := fn(in out e : E) -> u64 {
  match e {
    E::A(x) => { x }
    E::B(x, y) => { x + y }
  }
}

main := fn() -> u64 {
  mut v := P(x = 0, y = 0)
  via_ptr(ptr(mut v))         ## v = {1, 1}
  if legacy_caller() + v.x + v.y != 13 { return 1 }
  mut e := E.B(20, 22)
  if weight(e) != 42 { return 2 }
  mut s := P(x = 1, y = 0)
  bump(s, 5)                  ## s = {6, 1}
  twice(s)                    ## s = {11, 3}
  mut o := O(tag = 7, inner = P(x = 0, y = 0))
  bump(o.inner, 9)            ## o.inner = {9, 1}
  mut u := P(x = 0, y = 0)
  fill(u)                     ## u = {4, 5}
  legacy_bump(u)              ## u = {14, 5}
  ## 11 + 3 + 9 + 1 + 14 + 5 = 43, less (o.tag - 6) = 1
  s.x + s.y + o.inner.x + o.inner.y + u.x + u.y - (o.tag - 6)
}
