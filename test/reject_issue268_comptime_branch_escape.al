choose := fn(cond : bool) -> u64 {
  if cond {
    comptime x := 5
  } else {
    x := 7
  }
  return x
}

main := fn() -> u64 {
  return choose(true) + choose(false)
}
