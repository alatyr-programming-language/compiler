main := fn(x : u64) -> u64 {
  comptime bad : u64 = x
  return bad
}
