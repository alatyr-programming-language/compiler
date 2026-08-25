## BYTES negative: a direct indexed field write must respect the fixed array bound.
Pair := struct { x : u64 }
main := fn() -> u64 {
  mut xs : [Pair; 2] = [Pair(x = 0), Pair(x = 0)]
  xs[2].x = 1
  0
}
