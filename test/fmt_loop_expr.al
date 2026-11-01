main := fn() -> u64 {
  x : u64 = loop {
    break 42
  }
  return x
}
