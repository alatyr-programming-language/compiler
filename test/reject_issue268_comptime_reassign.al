main := fn() -> u64 {
  comptime bad : u64 = 5
  bad = 6
  return bad
}
