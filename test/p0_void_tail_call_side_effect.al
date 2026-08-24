## P0 ABI: a side-effecting call in the final expression position of a void
## function must not be discarded with its unused result.
bump := fn(p : ptr(mut u64), by : u64) {
  deref(p) = deref(p) + by
}

forward := fn(p : ptr(mut u64), by : u64) {
  bump(p, by)
}

main := fn() -> u64 {
  mut a : u64 = 0
  forward(ptr(mut a), 42)
  if a != 42 { return 1 }
  return 42
}
