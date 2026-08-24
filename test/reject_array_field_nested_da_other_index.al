Inner := struct { v : u64, w : u64 }
Outer := struct { xs : [Inner; 2] }
main := fn() -> u64 {
  mut p : Outer
  p.xs[0].v = 42
  return p.xs[1].v
}
