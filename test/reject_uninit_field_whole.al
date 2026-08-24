## A partial field write does not initialize the whole aggregate.
P := struct { a : u64, b : u64 }
main := fn() -> u64 {
  mut p : P
  p.a = 40
  return p
}
