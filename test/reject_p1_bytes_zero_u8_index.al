## P1-BYTES negative: indexing a zero-length byte array must fail loud at runtime.
main := fn() -> u64 {
  xs : [u8; 0] = [0; 0]
  xs[0]
}
