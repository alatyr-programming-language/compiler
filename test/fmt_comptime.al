main := fn() -> u64 {
  s := 0
  comptime for i in 0 .. 3 {
    s = s + i
  }
  return s + 39
}
