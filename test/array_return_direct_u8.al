## BYTES failing-first repro: a u8 fixed-array return indexed directly.
build := fn() -> [u8; 4] {
  mut t : [u8; 4] = [0; 4]
  t[2] = 42
  t
}

main := fn() -> u64 {
  mut k : usize = 2
  u64(build()[k])
}
