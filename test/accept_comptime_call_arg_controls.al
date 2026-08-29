take := fn(v : u64) -> u64 {
  return v
}

main := fn() -> u64 {
  mut runtime : u64 = 40
  if take(unchecked (18446744073709551615 + 1)) != 0 { return 1 }
  if take(runtime + 1) != 41 { return 2 }
  return 42
}
