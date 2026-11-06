main := fn() -> u64 {
  x : u64 = loop {
    break 42
  }
  return x
}
## expect(x86_64): run 42
