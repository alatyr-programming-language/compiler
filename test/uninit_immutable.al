## Types §9.4 first slice: an immutable uninitialized local permits exactly one first write.
main := fn() -> u64 {
  x : u64
  x = 41
  return x + 1
}
