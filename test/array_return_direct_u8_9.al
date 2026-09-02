## BYTES boundary: direct indexing of a [u8; 9] return selects either packed word — index 8 comes from
## the high word and index 2 from the low one, so the two reads sum to a value neither alone can make.
build := fn() -> [u8; 9] {
  mut t : [u8; 9] = [0; 9]
  t[2] = 5
  t[8] = 42
  t
}

main := fn() -> u64 {
  mut k : usize = 8
  mut j : usize = 2
  u64(build()[k]) + u64(build()[j])
}
