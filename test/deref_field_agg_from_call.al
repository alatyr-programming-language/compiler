## e2e — a MULTI-WORD struct FIELD written THROUGH a pointer from a struct-RETURNING CALL
## (`deref(p).i = mk()`) AND from an if-EXPRESSION with a CALL branch (`deref(p).i = if c { mk() } … `).
## Both previously FAILED LOUD (the scalar-field-through-pointer store moves ONE word → a multi-word
## field would drop payload words). Lower now materializes the RHS aggregate into the agg-temp block,
## loads the pointee pointer into %r13, and copies all the field's words ASCENDING into (wfi+j)*8(ptr) —
## the pointee field layout the nested READ uses. Verifies BOTH words land AND the neighbour field `t`
## is untouched. Neutral: src/+lib/ never write a multi-word field through a pointer this way.
Inner := struct { x : u64, y : u64 }
Outer := struct { i : Inner, t : u64 }
mk := fn() -> Inner { Inner(x = 40, y = 2) }
main := fn() -> u64 {
  mut o := Outer(i = Inner(x = 0, y = 0), t = 7)
  p := ptr(mut o)
  deref(p).i = mk()                                          ## struct-CALL through a pointer
  mut r : u64 = 0
  if o.i.x + o.i.y == 42 { r = r + 14 }
  c := true
  deref(p).i = if c { mk() } else { Inner(x = 0, y = 0) }    ## if-with-CALL-branch through a pointer
  if o.i.x + o.i.y == 42 { r = r + 14 }
  if o.t == 7 { r = r + 14 }                                 ## neighbour word intact (no over-write)
  r                                                          ## 42 iff both deliveries copied every word
}
