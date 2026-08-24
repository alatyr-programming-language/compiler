## The guard: `resolve_ty` leaves a `brand(U)` name and a generic instance (`Option(u64)`) UNKNOWN, and
## the rule never rejects on an unknown sink — brand identity and generic-payload conformance are not
## being judged here, so every one of these must stay accepted.
Id := brand(u64)
E := enum { A(u64), B }
main := fn() -> u64 {
  k : Id = Id(7)
  o : Option(u64) = Option(u64).Some(5)
  e : E = E.A(3)
  return u64(k) + o.unwrap()
}
