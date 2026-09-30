## e2e / issue #809 — a direct `match` over an `Option(ptr(T))` field the lowering could not type.
##
## A `match` over a folded `Option(ptr(T))` field was typed only for a local struct or a struct
## parameter. Reached through a mutable global (`G.head`), an array element (`ns[i].next`) or a pointer
## (`deref(p).next`, including a matched payload's `deref(q).next`), the lowering could not see the
## scrutinee's enum type and refused a valid program ("cannot see the scrutinee's enum type"). The
## field's declared type now names the fold, and the one folded word is staged and matched, in the
## statement, value and tail forms.
##
## 42 means every match held. Each miss owns its own code from 100 up.
N := struct { v : u64, next : Option(ptr(mut N)) }
H := struct { k : u64, head : Option(ptr(mut N)) }
mut G := H(k = 1, head = Option.None)

## tail form over a global's field
head_v := fn() -> u64 { match G.head { Some(q) => { deref(q).v }; None => { 7 } } }

## tail form over a field through a pointer parameter
next_v := fn(p : ptr(mut N)) -> u64 { match deref(p).next { Some(q) => { deref(q).v }; None => { 9 } } }

main := fn() -> u64 {
  mut c := N(v = 30, next = Option.None)
  mut b := N(v = 12, next = Option.Some(ptr(mut c)))
  ## a global's field: None, then Some, statement and value forms
  match G.head { Some(_q) => { return 100 }; None => {} }
  if head_v() != 7 { return 101 }
  G.head = Option.Some(ptr(mut b))
  match G.head { Some(q) => { if deref(q).v != 12 { return 102 } }; None => { return 103 } }
  r := match G.head { Some(q) => { deref(q).v }; None => { 104 } }
  if r != 12 or head_v() != 12 { return 105 }
  ## an array element's field
  mut ns := [N(v = 1, next = Option.None), N(v = 2, next = Option.Some(ptr(mut c)))]
  match ns[0].next { Some(_q) => { return 106 }; None => {} }
  match ns[1].next { Some(q) => { if deref(q).v != 30 { return 107 } }; None => { return 108 } }
  ## a field through a pointer, and through a matched payload pointer (the list walk's next hop)
  pb : ptr(mut N) = ptr(mut b)
  match deref(pb).next { Some(q) => { if deref(q).v != 30 { return 109 } }; None => { return 110 } }
  if next_v(ptr(mut c)) != 9 { return 111 }
  mut s : u64 = 0
  match G.head {
    Some(q) => {
      s = deref(q).v
      match deref(q).next { Some(r2) => { s = s + deref(r2).v }; None => { return 112 } }
    }
    None => { return 113 }
  }
  s
}
