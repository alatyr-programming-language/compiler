## BYTES boundary: direct indexing of a [u8; 16] return selects its last byte.
build := fn() -> [u8; 16] {
  mut t : [u8; 16] = [0; 16]
  t[15] = 42
  t
}

main := fn() -> u64 {
  mut k : usize = 15
  u64(build()[k])
}
