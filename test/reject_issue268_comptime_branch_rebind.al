choose := fn(cond : bool) -> u64 {
  comptime x := 5
  if cond {
    x := 7
  }
  return x
}

main := fn() -> u64 {
  return choose(true) + choose(false)
}
