Inner := struct { v : u64, w : u64 }
Outer := struct { xs : [Inner; 2] }
main := fn() -> u64 {
  mut p : Outer
  if true { p.xs[0].v = 20 } else { p.xs[0].v = 22 }
  return p.xs[0].v * 2
}
