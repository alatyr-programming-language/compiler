## `==` / `!=` over PAYLOAD-carrying enums must link and compute correctly (regression lock for the
## PRIMARY bug: a bare `==` on payload enum locals linked to an UNDEFINED `base__derive__eq__<E>`
## because the mono pre-pass couldn't infer an inferred enum local's type — `block_decl_type` only
## resolved struct-literal RHSs, not enum literals — so the derive instance was never collected; and
## the derive enum arm's implicit `eq(pa, pb)` recursion mis-inferred the payload type as the VARIABLE
## NAME `pa`, now routed through the bare `==` operator which resolves the type from the slot).

E := enum { A(u64), B(u64) }

main := fn() -> u64 {
  o1 := Option.Some(20)
  o2 := Option.Some(20)
  a := E.A(1)
  b := E.B(1)
  mut r := 0
  if o1 == o2 { r = r + 20 }   ## same variant + equal payload -> equal -> +20
  if a != b { r = r + 22 }     ## different variant -> not equal -> +22
  return r                     ## 42
}
