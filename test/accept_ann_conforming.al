## The guard against a false reject on every conforming shape the widened rule sits next to: a bool
## literal into `bool`, an array literal into `[T; N]`, an integer literal into a pointer sink (the
## usize<->ptr seam the checker accepts by design, MEM-7/8), and an `f64` annotation the checker
## cannot classify at all (it stays accepted rather than guessed at).
main := fn() -> u64 {
  b : bool = true
  a : [u64; 2] = [3, 4]
  p : ptr(u8) = 0
  f : f64 = 1.5
  if b { return a[0] + a[1] }
  return 0
}
