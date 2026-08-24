## Types §9.4 next slice: assignment on only one non-diverging arm is not definite assignment.
main := fn() -> u64 {
  mut x : u64
  if true { x = 41 }
  return x
}
