## A dynamic-index write remains conservative and cannot initialize a known element.
main := fn() -> u64 {
  mut xs : [u64; 2]
  mut i : u64 = 0
  xs[i] = 42
  return xs[0]
}
