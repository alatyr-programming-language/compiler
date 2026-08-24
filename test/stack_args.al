sum8 := fn(a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64) -> u64 {
  return a + b + c + d + e + f + g + h
}

main := fn() -> u64 {
  return sum8(1, 2, 3, 4, 5, 6, 7, 14)
}
