## e2e / issue #789 — the idiomatic walk of a linked structure through `Option(ptr(T))`.
##
## `Option(ptr(T))` is one folded word (None = 0, Some(p) = p), but a BARE variant literal —
## `Option.Some(p)` / `Option.None`, whose head names no type argument — was folded only where its
## position was a struct field or an annotated local. Passed straight to an `Option(ptr(T))` parameter
## it was materialized as the two-word `[disc, payload]` block, and the callee read the discriminant as
## the pointer: the first `deref` of the payload was a SIGSEGV (`match h { Some(q) => deref(q) … }` over a
## parameter, or over a local bound from one). Re-assigning a folded local from one (`p = Option.None` in
## the loop) was refused as a wider "NARROWER binding" re-binding. The literal now takes the fold of the
## type its position expects: the parameter's, or the destination local's.
##
## 42 means every walk held. Each miss owns its own code from 100 up.
N := struct { v : u64, next : Option(ptr(mut N)) }

## the issue's probe b: match a parameter, copy the pointee
param_match := fn(h : Option(ptr(mut N))) -> u64 {
  match h { Some(q) => { nd : N = deref(q); return nd.v }; None => { return 1 } }
  return 2
}

## probe c: the same through an annotated local bound from the parameter
local_from_param := fn(h : Option(ptr(mut N))) -> u64 {
  p : Option(ptr(mut N)) = h
  match p { Some(q) => { nd : N = deref(q); return nd.v }; None => { return 1 } }
  return 2
}

## probe d: re-assign the local from a field of the copied pointee, then match again
reassign_from_field := fn(h : Option(ptr(mut N))) -> u64 {
  mut p : Option(ptr(mut N)) = h
  match p { Some(q) => { nd : N = deref(q); p = nd.next }; None => { return 1 } }
  match p { Some(q) => { nd : N = deref(q); return nd.v }; None => { return 3 } }
  return 2
}

## probe e: a loop that re-assigns the local from a bare `Option.None`
count_one := fn(h : Option(ptr(mut N))) -> u64 {
  mut p : Option(ptr(mut N)) = h
  mut s : u64 = 0
  loop { match p { Some(_q) => { s = s + 1; p = Option.None }; None => { break } } }
  s
}

## probe o1: the full walk, the pointee copied to a local
sum_copy := fn(head : Option(ptr(mut N))) -> u64 {
  mut s : u64 = 0
  mut p : Option(ptr(mut N)) = head
  loop { match p { Some(q) => { nd : N = deref(q); s = s + nd.v; p = nd.next }; None => { break } } }
  s
}

## the walk read through the payload pointer, the local unannotated
sum_deref := fn(head : Option(ptr(mut N))) -> u64 {
  mut s : u64 = 0
  mut p := head
  loop { match p { Some(q) => { s = s + deref(q).v; p = deref(q).next }; None => { break } } }
  s
}

## a `mut` write through the payload pointer on every node
bump := fn(head : Option(ptr(mut N))) {
  mut p := head
  loop { match p { Some(q) => { deref(q).v = deref(q).v + 1; p = deref(q).next }; None => { break } } }
}

## the Option handed on inside the loop, in every form
val := fn(o : Option(ptr(mut N))) -> u64 { match o { Some(q) => { return deref(q).v }; None => { return 0 } }; 0 }
sum_handoff := fn(head : Option(ptr(mut N))) -> u64 {
  mut s : u64 = 0
  mut p : Option(ptr(mut N)) = head
  loop {
    match p {
      Some(q) => { s = s + val(p) + val(deref(q).next) + val(Option.Some(q)) + val(Option.None); p = deref(q).next }
      None => { break }
    }
  }
  s
}

## the Option returned from a function, both variants spelled bare
nxt := fn(q : ptr(mut N)) -> Option(ptr(mut N)) { deref(q).next }
find := fn(h : Option(ptr(mut N)), k : u64) -> Option(ptr(mut N)) {
  mut p := h
  loop {
    match p {
      Some(q) => { if deref(q).v == k { return Option.Some(q) }; p = nxt(q) }
      None => { return Option.None }
    }
  }
  Option.None
}

main := fn() -> u64 {
  mut c := N(v = 30, next = Option.None)
  mut b := N(v = 10, next = Option.Some(ptr(mut c)))
  mut a := N(v = 2, next = Option.Some(ptr(mut b)))
  if param_match(Option.Some(ptr(mut c))) != 30 { return 100 }
  if param_match(Option.None) != 1 { return 101 }
  if local_from_param(Option.Some(ptr(mut b))) != 10 { return 102 }
  if reassign_from_field(Option.Some(ptr(mut b))) != 30 { return 103 }
  if reassign_from_field(Option.Some(ptr(mut c))) != 3 { return 104 }
  if count_one(Option.Some(ptr(mut c))) != 1 { return 105 }
  if count_one(Option.None) != 0 { return 106 }
  if sum_copy(Option.Some(ptr(mut a))) != 42 { return 107 }
  if sum_deref(Option.Some(ptr(mut a))) != 42 { return 108 }
  bump(Option.Some(ptr(mut a)))
  if a.v + b.v + c.v != 45 { return 109 }
  ## a: 3+11+3+0, b: 11+31+11+0, c: 31+0+31+0
  if sum_handoff(Option.Some(ptr(mut a))) != 132 { return 110 }
  match find(Option.Some(ptr(mut a)), 99) { Some(_q) => { return 111 }; None => {} }
  f := find(Option.Some(ptr(mut a)), 11)
  match f { Some(q) => { if deref(q).v != 11 { return 112 } }; None => { return 113 } }
  ## a local that starts at None and is re-assigned a bare Some
  mut o : Option(ptr(mut N)) = Option.None
  match o { Some(_q) => { return 114 }; None => {} }
  o = Option.Some(ptr(mut c))
  match o { Some(q) => { if deref(q).v != 31 { return 115 } }; None => { return 116 } }
  sum_copy(Option.Some(ptr(mut b)))
}
