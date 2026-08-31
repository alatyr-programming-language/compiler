## BYTES carrier forwarding: a fixed-array parameter can return its two packed words.
forward := fn(a : [u8; 16]) -> [u8; 16] {
  a
}

main := fn() -> u64 {
  mut t : [u8; 16] = [0; 16]
  t[15] = 42
  u64(forward(t)[15])
}
