## The guard, in two halves that no longer share a reason. GENERIC-PAYLOAD conformance is still not
## judged: `resolve_ty` leaves a generic instance (`Option(u64)`) UNKNOWN and the rule never rejects
## on an unknown sink. BRAND identity, on the other hand, IS judged now — #310 gave a direct
## `brand(U)` name a nominal identity and #299 turned that identity into the Types §4.2/§4.3 refusal.
## `k : Id = Id(7)` and `u64(k)` survive it because they were already the EXPLICIT spellings §4.2
## prescribes, which is why this fixture needed no splitting: measured over every tracked fixture, the
## refusal moved no diagnostic byte and no emitted byte. Every one of these must stay accepted.
Id := brand(u64)
E := enum { A(u64), B }
main := fn() -> u64 {
  k : Id = Id(7)
  o : Option(u64) = Option(u64).Some(5)
  e : E = E.A(3)
  return u64(k) + o.unwrap()
}
