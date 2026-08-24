main := fn() -> u64 {
  x : i64 = 0 - 17
  q := x / 5
  r := x % 5
  if q == (0 - 3) {
    if r == (0 - 2) { return 42 }
  }
  return 1
}
