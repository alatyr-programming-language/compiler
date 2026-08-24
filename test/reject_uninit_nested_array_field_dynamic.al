P := struct { xs : [u64; 2], z : u64 }
main := fn() -> u64 {
  mut p : P
  mut i : u64 = 0
  p.xs[i] = 42
  return p.xs[0]
}
