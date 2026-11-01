## expect: run 42
main := fn() -> u64 {
  x := loop {
    break 42
  }
  return x
}
