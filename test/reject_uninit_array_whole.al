## Partial element initialization does not make the whole array readable.
main := fn() -> u64 {
  mut xs : [u64; 2]
  xs[0] = 42
  return xs
}
