## Types §9.4 next slice: a diverging arm contributes no path to definite assignment.
main := fn() -> u64 {
  mut x : u64
  if true { return 1 } else { x = 41 }
  return x + 1
}
