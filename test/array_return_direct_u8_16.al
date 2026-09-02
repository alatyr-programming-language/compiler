## BYTES boundary: direct indexing of a [u8; 16] return selects either packed word — index 15 comes
## from the high word and index 2 from the low one, so the two reads sum to a value neither alone can
## make.
build := fn() -> [u8; 16] {
  mut t : [u8; 16] = [0; 16]
  t[2] = 5
  t[15] = 42
  t
}

main := fn() -> u64 {
  mut k : usize = 15
  mut j : usize = 2
  u64(build()[k]) + u64(build()[j])
}
