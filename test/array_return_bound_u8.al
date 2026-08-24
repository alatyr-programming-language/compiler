## P1-BYTES failing-first repro: a u8 fixed-array return bound to a local and indexed.
## This must not silently read a scalar slot or return registers.
build := fn() -> [u8; 4] {
  mut t : [u8; 4] = [0; 4]
  t[2] = 42
  t
}

main := fn() -> u64 {
  mut k : usize = 2
  r := build()
  u64(r[k])
}
