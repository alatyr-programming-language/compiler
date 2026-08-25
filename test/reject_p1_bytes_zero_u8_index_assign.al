## BYTES negative: a direct write through a local `[u8; 0]` has no valid element address.
main := fn() -> u64 {
  mut xs : [u8; 0] = [0; 0]
  xs[0] = 1
  0
}
