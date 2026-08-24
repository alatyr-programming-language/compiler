fact := fn(n : u64) -> u64 {
  mut r := 1
  mut i := 1
  while i <= n { r = r * i
    i = i + 1 }
  return r
}
main := fn() -> u64 { return fact(5) }
