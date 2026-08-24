## e2e (P3, decl-position effectors): a DIRECT `@owning struct` (linearity) and an `@inline` fn
## (an optimization hint) — both stdlib-pervasive prefixes the lean parser now accepts. `@owning`
## is a checker concern and `@inline` a codegen hint, so both are consumed with no codegen effect (the
## struct lowers as a plain one, the fn as an ordinary definition). Expected exit: 42.
Thing := @owning struct { a : usize, b : usize }
@inline add := fn(x : usize, y : usize) -> usize { return x + y }
main := fn() -> u64 {
  t := Thing(a = 30, b = 12)
  return u64(add(t.a, t.b))
}
