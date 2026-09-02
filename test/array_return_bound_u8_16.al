## BYTES boundary: a [u8; 16] return uses both packed words after binding.
build := fn() -> [u8; 16] {
  mut t : [u8; 16] = [0; 16]
  t[15] = 42
  t
}

main := fn() -> u64 {
  mut k : usize = 15
  r := build()
  u64(r[k])
}
