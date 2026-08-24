## Focused Grammar §2.4 reject: a hex-float exponent is decimal and needs digits after `p`/`P`.
main := fn() -> u64 {
  x : f64 = 0x1p+q
  return u64(x)
}
