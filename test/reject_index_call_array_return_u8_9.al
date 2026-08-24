## P1-BYTES control: the one-word bounded ABI stops at N = 8. A direct [u8; 9] call result
## remains a located reject rather than truncating the ninth byte.
build := fn() -> [u8; 9] {
  mut t : [u8; 9] = [0; 9]
  t[8] = 42
  t
}

main := fn() -> u64 {
  mut k : usize = 8
  u64(build()[k])
}
