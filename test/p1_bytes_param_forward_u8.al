## P1-BYTES caller-side seam: explicitly forward a bounded byte-array return
## through another `[u8; N]` function's return. The caller reads the carrier.
build := fn() -> [u8; 4] {
  mut t : [u8; 4] = [0; 4]
  t[2] = 42
  t
}

relay := fn() -> [u8; 4] {
  return build()
}

main := fn() -> u64 {
  u64(relay()[2])
}
