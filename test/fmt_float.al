## fmt — a FLOAT literal (`Expr::FloatLit`) must round-trip through `alatyr fmt` (idempotent) and the
## reformatted source still build+run. `u64(42.5)` truncates to 42.
main := fn() -> u64 {
  f : f64 = 42.5
  u64(f)
}
