## overload resolution: an overload set discriminated solely by a FLOAT-vs-INT parameter
## must resolve a bare FLOAT-literal argument (`g(2.0)` → `g(f64)`), the float mirror of the existing
## integer-literal rule. Previously a float literal was not classified, so `g(2.0)` matched BOTH
## `g(u64)` and `g(f64)` as a wildcard → the call was ambiguous → no per-signature suffix → a bare
## `<module>__g` callee label that no definition emitted → an `undefined reference` at link (rc 14).
g := fn(x : u64) -> u64 { return x + 100 }
g := fn(x : f64) -> u64 { return u64(x) + 200 }
main := fn() -> u64 {
  a := g(10)         ## integer literal → g(u64) → 110
  b := g(2.0)        ## float literal → g(f64) → 202
  return b - a - 50  ## 202 - 110 - 50 = 42
}
