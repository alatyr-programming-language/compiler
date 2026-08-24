## Focused Grammar §2.4 reject: a C-style hex float must carry a `p`/`P` binary exponent.
main := fn() -> u64 {
  x : f64 = 0x1.0
  return u64(x)
}
