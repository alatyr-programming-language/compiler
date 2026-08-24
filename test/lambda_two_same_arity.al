## FN-6 — TWO lambdas of the SAME arity in one fn. Both lifted lambdas carry the SENTINEL empty name
## (`name_len == 0`); the duplicate-decl check compared their names equal (empty == empty) and, since
## they share an arity, `same_fn_signature` marked the second a DUPLICATE — a false rejection of a
## program that builds and runs fine. A lambda is unique by its `fn`-offset, never a duplicate.
## `app(a, 20)` = 40, `app(b, 0)` = 2 → 42.
app := fn(g : u64, x : u64) -> u64 { return g(x) }
main := fn() -> u64 {
  a := fn(n : u64) -> u64 { return n * 2 }
  b := fn(n : u64) -> u64 { return n + 2 }
  return app(a, 20) + app(b, 0)
}
