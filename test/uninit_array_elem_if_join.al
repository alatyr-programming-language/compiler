## The same constant element written on every branch is initialized after the join.
main := fn() -> u64 {
  mut xs : [u64; 2]
  if true { xs[0] = 20 } else { xs[0] = 22 }
  return xs[0] * 2
}
