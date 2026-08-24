## e2e — Functions §1.4 / Types §6.4: an AGGREGATE ARRAY ELEMENT (`ps[i]` over a `[P; N]` / `[E; N]`)
## passed as a plain call ARGUMENT is passed BY REFERENCE, like every other by-value aggregate value.
##
## What was wrong: a raw SIGSEGV, with no comparison or nesting involved — `take(ps[0])` alone faulted.
## The operand fell to the scalar default in `emit_arg`, i.e. `emit_gas`'s `Index` arm, which computes
## the element's address correctly and then DEREFERENCES it (`movq (%rax), %rax`), handing the callee
## the element's FIRST FIELD VALUE as its by-reference block pointer; the callee dereferenced that
## integer. An aggregate ELEMENT is a PLACE, not a scalar value — `emit_index_addr` already composes
## its word-0 address for every base, so the address is now pushed instead of loaded through.
##
## Covers every spelling that faulted: a CONSTANT index, a RUNTIME index, a 1-word struct element, a
## multi-word struct element, an ENUM element, a NON-FIRST argument position, an element of a by-ref
## `[P; N]` PARAM, and an element of a `Slice(P)` PARAM. 3 + 7 + 2 + 3 + 5 + 8 + 7 + 7 = 42.
P := struct { x : u64, y : u64 }
Q := struct { x : u64 }
E := enum { A(u64), B(u64) }
take := fn(p : P) -> u64 { p.x + p.y }
takeq := fn(q : Q) -> u64 { q.x }
takee := fn(e : E) -> u64 {
  match e {
    E::A(v) => { v }
    E::B(v) => { v + 1 }
  }
}
second := fn(k : u64, p : P) -> u64 { k + p.x + p.y }
via_param := fn(ps : [P; 2]) -> u64 { take(ps[1]) }
via_slice := fn(s : Slice(P)) -> u64 { take(s[1]) }
main := fn() -> u64 {
  ps : [P; 2] = [P(x = 1, y = 2), P(x = 3, y = 4)]
  mut acc : u64 = 0
  acc = acc + take(ps[0])          ## constant index, multi-word element  -> 3
  mut i := 1
  acc = acc + take(ps[i])          ## runtime index                       -> 7
  qs : [Q; 2] = [Q(x = 5), Q(x = 2)]
  acc = acc + takeq(qs[1])         ## ONE-word struct element             -> 2
  es : [E; 2] = [E.A(3), E.B(4)]
  acc = acc + takee(es[0])         ## enum element (variant A)            -> 3
  acc = acc + takee(es[1])         ## enum element (variant B)            -> 5
  acc = acc + second(1, ps[1])     ## NON-FIRST argument position         -> 8
  acc = acc + via_param(ps)        ## element of a by-ref `[P; 2]` PARAM  -> 7
  sl := ps[0..2]
  acc = acc + via_slice(sl)        ## element of a `Slice(P)` PARAM       -> 7
  return acc
}
