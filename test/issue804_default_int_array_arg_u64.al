## Issue #804 / Types §4.3 — the same default-typed `[i64; 3]` passed where `[u64; 3]` is declared:
## `i64` to `u64` crosses signedness, a numeric conversion, never an implicit one. The parent accepted it.
f := fn(xs : [u64; 3]) -> u64 { return xs[2] }
main := fn() -> u64 {
  a := [1, 7, 42]
  return f(a)
}
