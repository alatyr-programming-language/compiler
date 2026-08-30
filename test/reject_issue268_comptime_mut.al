main := fn() -> u64 {
  comptime mut bad : u64 = 5
  return bad
}
