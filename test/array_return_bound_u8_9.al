## BYTES boundary: a [u8; 9] return uses two packed words after binding.
build := fn() -> [u8; 9] {
  mut t : [u8; 9] = [0; 9]
  t[8] = 42
  t
}

main := fn() -> u64 {
  mut k : usize = 8
  r := build()
  u64(r[k])
}
