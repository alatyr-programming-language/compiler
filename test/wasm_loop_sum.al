sum := fn(n : u64) -> u64 {
  mut acc := 0
  mut i := 0
  while i < n { acc = acc + i
    i = i + 1 }
  return acc
}
main := fn() -> u64 { return sum(9) }
