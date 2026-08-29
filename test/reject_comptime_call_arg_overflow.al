take := fn(v : u64) -> u64 {
  return v
}

main := fn() -> u64 {
  return take(18446744073709551615 + 1)
}
