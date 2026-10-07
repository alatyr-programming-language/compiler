fact := fn(n : u64) -> u64 {
  mut r : u64 = 1
  mut i : u64 = 1
  while i <= n { r = r * i
    i = i + 1 }
  return r
}
main := fn() -> u64 { return fact(5) }
