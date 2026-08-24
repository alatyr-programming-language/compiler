## Types §9.4 first slice: a typed local without an initializer is valid after a definite write.
main := fn() -> u64 {
  mut x : u64
  x = 41
  return x + 1
}
