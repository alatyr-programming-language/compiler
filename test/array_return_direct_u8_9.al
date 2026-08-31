## BYTES boundary: direct indexing of a [u8; 9] return selects its high packed word.
build := fn() -> [u8; 9] {
  mut t : [u8; 9] = [0; 9]
  t[8] = 42
  t
}

main := fn() -> u64 {
  mut k : usize = 8
  u64(build()[k])
}
