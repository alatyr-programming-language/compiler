## BYTES control: a bound [u8; 17] return is wider than the two-word increment and must reject
## with the out-of-range fixed-array return shape, rather than bind as a scalar.
build := fn() -> [u8; 17] {
  mut t : [u8; 17] = [0; 17]
  t[16] = 42
  t
}

main := fn() -> u64 {
  mut k : usize = 16
  r := build()
  u64(r[k])
}
