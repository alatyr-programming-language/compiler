## Types §9.4: branch divergence keeps the continuing nested array-field write.
Inner := struct { v : u64, w : u64 }
Outer := struct { xs : [Inner; 2] }
main := fn() -> u64 {
  mut p : Outer
  if true { p.xs[0].w = 42 } else { return 0 }
  return p.xs[0].w
}
