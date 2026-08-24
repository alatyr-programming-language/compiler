## Regression: a generic fn returning a generic enum whose payload is the callee's own
## type-param (`Opt(T)`), called with a STRUCT type-arg, bound to a local, then matched.
## The result binding must SIZE + STAGE + MATCH the payload as the concrete struct (Pt = 3
## words), not as the un-substituted type-param `T` (1 scalar word). Exercises the pervasive
## generic-enum-return-substitution path.
Pt := struct { x : u64, y : u64 }
Opt := fn(T : type) -> type { return enum { None, Some(T) } }

wrap := fn(T : type, v : T) -> Opt(T) {
  c := v
  return Opt(T).Some(c)
}

main := fn() -> u64 {
  om := wrap(Pt, Pt(x = 40, y = 2))
  match om {
    Some(p) => { return p.x + p.y }
    None => { return 0 }
  }
}
