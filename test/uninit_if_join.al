## Types §9.4 next slice: a local assigned on every if arm is initialized after the join.
main := fn() -> u64 {
  mut x : u64
  if true { x = 20 } else { x = 22 }
  return x * 2
}
