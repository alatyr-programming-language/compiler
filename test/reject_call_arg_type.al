takes_bool := fn(value : bool) -> u64 {
  if value { return 1 }
  return 0
}

main := fn() -> u64 {
  return takes_bool(42)
}
