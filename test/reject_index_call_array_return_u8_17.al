## BYTES control: the two-word bounded ABI stops at N = 16. A direct [u8; 17] call result
## remains a located reject rather than truncating the seventeenth byte.
build := fn() -> [u8; 17] {
  mut t : [u8; 17] = [0; 17]
  t[16] = 42
  t
}

main := fn() -> u64 {
  mut k : usize = 16
  u64(build()[k])
}
