## P1-BYTES control: the bounded lane is u8-only. A direct [i8; 4] call result remains a
## located reject instead of reusing the unsigned packed-byte ABI without a signedness decision.
build := fn() -> [i8; 4] {
  mut t : [i8; 4] = [0; 4]
  t[2] = 42
  t
}

main := fn() -> u64 {
  mut k : usize = 2
  u64(build()[k])
}
