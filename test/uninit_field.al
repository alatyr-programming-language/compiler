## Types §9.4 direct-field slice: each field write initializes only that field.
P := struct { a : u64, b : u64 }
main := fn() -> u64 {
  mut p : P
  p.a = 40
  p.b = 2
  return p.a + p.b
}
