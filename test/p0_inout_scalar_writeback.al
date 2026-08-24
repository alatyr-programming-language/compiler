## P0 ABI: an in out scalar is a caller place, not a copied value.
bump := fn(in out a : u64, p : ptr(mut u64), by : u64) {
  a = a + by
  deref(p) = deref(p) + by
}

main := fn() -> u64 {
  mut a : u64 = 0
  mut b : u64 = 0
  bump(a, ptr(mut b), 42)
  if a != 42 { return 1 }
  if b != 42 { return 2 }
  return 42
}
