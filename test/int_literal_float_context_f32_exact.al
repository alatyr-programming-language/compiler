main := fn() -> u64 {
  x : f32 = 16777217 - 1
  if u64(x) != 16777216 { return 1 }
  42
}
