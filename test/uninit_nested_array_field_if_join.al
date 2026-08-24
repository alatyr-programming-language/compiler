P := struct { xs : [u64; 2], z : u64 }
main := fn() -> u64 {
  mut p : P
  if true { p.xs[0] = 20 } else { p.xs[0] = 22 }
  return p.xs[0] * 2
}
