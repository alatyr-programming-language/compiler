## Types §9.4 first slice: an uninitialized aggregate reserves its declared width before whole assignment.
P := struct { x : u64, y : u64 }
main := fn() -> u64 {
  mut p : P
  p = P(x = 4, y = 5)
  return p.x + p.y
}
