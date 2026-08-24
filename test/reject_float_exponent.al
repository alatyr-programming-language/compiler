## Focused Grammar §2.4 reject: an exponent must contain a decimal digit after its optional sign.
main := fn() -> u64 {
  x : f64 = 1e+
  return u64(x)
}
