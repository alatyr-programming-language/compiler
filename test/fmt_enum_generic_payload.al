## fmt fixture / issue #856 — a single-payload enum variant whose payload type is an APPLICATION.
##
## The FieldDecl type span is only the payload's head token, and fmt rendered an arity-1 variant from
## that span, so `B(ptr(u64))` came back as `B(ptr)` and `C(Option(u64))` as `C(Option)`. The output
## still compiled (#857) and was idempotent, so only the rendered text can tell. Every payloaded
## variant now copies its `( … )` group verbatim from source, as the multi-payload arm already did.
##
## 42 means each payload round-tripped its value. Each miss owns its own code from 100 up. The pointer
## payloads point at a `u64`, not a struct: a field read through a payload binding is #858.

E := enum { A(u64), B(ptr(u64)), C(Option(u64)), D(u64, ptr(u64)), Z }

get := fn(e : E) -> u64 {
  match e {
    A(k) => { return k }
    B(p) => { return deref(p) }
    C(o) => { match o { Some(k) => { return k }; None => { return 0 } } }
    D(k, p) => { return k + deref(p) }
    Z => { return 0 }
  }
  0
}

main := fn() -> u64 {
  n : u64 = 7
  if get(E.A(5)) != 5 { return 100 }
  if get(E.B(ptr(n))) != 7 { return 101 }
  if get(E.C(Option.Some(9))) != 9 { return 102 }
  if get(E.C(Option.None)) != 0 { return 103 }
  if get(E.D(14, ptr(n))) != 21 { return 104 }
  if get(E.Z) != 0 { return 105 }
  42
}
