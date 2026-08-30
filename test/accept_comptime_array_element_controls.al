main := fn() -> u64 {
  mut runtime : u64 = 40
  xs : [u64; 2] = [unchecked (18446744073709551615 + 1), runtime + 1]
  if xs[0] != 0 { return 1 }
  if xs[1] != 41 { return 2 }
  return 42
}
