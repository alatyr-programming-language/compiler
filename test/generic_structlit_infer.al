## §3/CT: a generic fn's implicit type parameter inferred from a struct-LITERAL value argument (not the
## first arg). `g(m, W(v=32))` — T is inferred as W from the 2nd value arg, and both the resolution and
## the monomorph instance-tag agree (previously the tag mis-resolved to the first arg). 10 + 32 = 42.
W := struct { v : u64 }

g := fn(T : type, k : u64, w : T) -> u64 {
  return k + w.v
}

main := fn() -> u64 {
  m : u64 = 10
  return g(m, W(v = 32))
}
