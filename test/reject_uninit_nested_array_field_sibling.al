P := struct { xs : [u64; 2], z : u64 }
main := fn() -> u64 {
  mut p : P
  p.xs[0] = 42
  return p.xs[1]
}
