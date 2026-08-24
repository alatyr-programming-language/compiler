## e2e — the FUNCTION-SCOPE mirror of `reject_comptime_overflow_global`: the same CT-12 rule applies
## to a local binding's comptime-constant initializer. Located at the arithmetic (line 4).
main := fn() -> i64 {
  x : i64 = 9223372036854775807 + 1
  return x
}
