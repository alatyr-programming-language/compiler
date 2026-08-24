## e2e (COMPTIME enum derive — the RECURSIVE `hash(p)` with an IMPLICIT payload type-arg). The full
## enum branch of `base/derive`'s structural `hash`: `match v { comptime for var in
## typeinfo(T).variants { T.(var)(p) => return hash(p) } }` unrolls into one arm per variant; the arm
## binds the payload `p` and recurses `hash(p)`. `hash(p)` has NO explicit type-arg — the lean lower
## resolves it to the payload's OWN type (the arm's payload type), routing to `hash__<payloadtype>`,
## and the mono worklist instantiates it per variant. `hash(E, E.A(42))` → arm A → `hash(u64, 42)` →
## the scalar branch `u64(v)` = 42. Enum dispatch + payload binding + implicit-type-arg recursion.
E := enum { A(u64), B(u64) }
hash := fn(T : type, v : T) -> u64 {
  comptime if (match typeinfo(T) { Enum(_) => true; _ => false }) {
    match v {
      comptime for var in typeinfo(T).variants {
        T.(var)(p) => { return hash(p) }
      }
    }
    return 0
  } else {
    return u64(v)
  }
}
main := fn() -> u64 {
  hash(E, E.A(42))
}
