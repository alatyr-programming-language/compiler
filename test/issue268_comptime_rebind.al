seq := fn() -> u64 {
  comptime x := 5
  x := 7
  return x
}

branch := fn(cond : bool) -> u64 {
  if cond {
    comptime x := 5
    return x
  } else {
    x := 7
    return x
  }
}

block := fn() -> u64 {
  if true {
    comptime x := 5
    if x != 5 { return 1 }
  }
  x := 7
  return x
}

main := fn() -> u64 {
  return seq() + branch(true) + branch(false) + block()
}
