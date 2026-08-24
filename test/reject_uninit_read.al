## Types §9.4: reading an uninitialized local is forbidden in checked code.
main := fn() -> u64 {
  mut x : u64
  return x
}
