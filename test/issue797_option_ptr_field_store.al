## e2e / issue #797 — storing a `Some(...)` literal into an `Option(ptr(T))` struct field.
##
## `Option(ptr(T))` is one folded word (None = 0, Some(p) = p). A field STORE pushed its value with the
## plain scalar lowering, and that pushes a `0` placeholder for every enum literal with a payload. So
## `a.next = Option.Some(ptr(mut b))` stored None, and a later `match` took the `None` arm: a silent
## wrong value on a clean build, with the bare `Option.Some` head and the typed `Option(ptr(T)).Some` head
## alike. Every field-store form now pushes the one folded word: a local's field, a field through a
## pointer (`deref(p).f`, `p.f`), a by-reference parameter's field, a nested field, a global's field and
## an array element's field. The list-building loop is the shape that matters.
##
## 42 means every store held. Each miss owns its own code from 100 up.
N := struct { v : u64, next : Option(ptr(mut N)) }
O := struct { k : u64, h : N }
H := struct { k : u64, head : Option(ptr(mut N)) }
mut G := H(k = 1, head = Option.None)

sum := fn(h : Option(ptr(mut N))) -> u64 {
  mut s : u64 = 0
  mut p := h
  loop { match p { Some(q) => { s = s + deref(q).v; p = deref(q).next }; None => { break } } }
  s
}

## a field through a pointer parameter, and through a by-reference struct parameter
link := fn(p : ptr(mut N), q : ptr(mut N)) { p.next = Option.Some(q) }
link_ref := fn(in out a : N, q : ptr(mut N)) { a.next = Option.Some(q) }

main := fn() -> u64 {
  mut c := N(v = 30, next = Option.None)
  mut b := N(v = 10, next = Option.None)
  mut a := N(v = 2, next = Option.None)
  ## a local's field, bare head
  a.next = Option.Some(ptr(mut b))
  match a.next { Some(q) => { if deref(q).v != 10 { return 100 } }; None => { return 101 } }
  ## a field through `deref(p)`, typed head
  pb := ptr(mut b)
  deref(pb).next = Option(ptr(mut N)).Some(ptr(mut c))
  match b.next { Some(q) => { if deref(q).v != 30 { return 102 } }; None => { return 103 } }
  if sum(Option.Some(ptr(mut a))) != 42 { return 104 }
  ## None still stores None, through the payload pointer
  match a.next { Some(q) => { deref(q).next = Option.None }; None => { return 105 } }
  if sum(Option.Some(ptr(mut a))) != 12 { return 106 }
  ## the list-building loop: append each node at the tail
  mut ns := [N(v = 0, next = Option.None), N(v = 0, next = Option.None), N(v = 0, next = Option.None)]
  mut head := N(v = 30, next = Option.None)
  mut tail : ptr(mut N) = ptr(mut head)
  mut i : u64 = 0
  while i < 3 {
    nd : ptr(mut N) = ptr(mut ns[i])
    deref(nd).v = i + 1
    deref(tail).next = Option.Some(nd)
    tail = nd
    i = i + 1
  }
  if sum(Option.Some(ptr(mut head))) != 36 { return 107 }
  ## a nested field
  mut o := O(k = 1, h = N(v = 2, next = Option.None))
  o.h.next = Option.Some(ptr(mut c))
  if sum(o.h.next) + o.h.v != 32 { return 108 }
  ## a global's field
  G.head = Option.Some(ptr(mut c))
  gh : Option(ptr(mut N)) = G.head
  if sum(gh) != 30 { return 109 }
  ## an array element's field
  ns[2].next = Option.Some(ptr(mut c))
  if sum(Option.Some(ptr(mut head))) != 66 { return 110 }
  ## through a pointer parameter and a by-reference parameter
  mut x := N(v = 5, next = Option.None)
  mut y := N(v = 7, next = Option.None)
  link(ptr(mut x), ptr(mut y))
  link_ref(y, ptr(mut c))
  sum(Option.Some(ptr(mut x)))
}
