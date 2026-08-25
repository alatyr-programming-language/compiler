## BYTES negative: a direct write at index 2 is outside the local `[u64; 2]` bound.
main := fn() -> u64 {
  mut xs : [u64; 2] = [0, 0]
  xs[2] = 1
  0
}
