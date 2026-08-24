clamp := fn(v : u64) -> u64 {
  lim := 42
  return if v > lim { lim } else { v }
}
main := fn() -> u64 { return clamp(100) }
