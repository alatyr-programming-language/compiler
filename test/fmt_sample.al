add := fn(a : u64, b : u64) -> u64 {
  s := a + b
  return s
}
main := fn() -> u64 {
  x := add(40, 2)
  if x > 0 {
    return x
  }
  return 0
}
