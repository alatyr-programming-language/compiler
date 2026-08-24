## Types §9.4: writing one nested leaf does not ready sibling leaf or whole aggregate.
Leaf := struct { x : u64, y : u64 }
Cell := struct { inner : Leaf, z : u64 }
main := fn() -> u64 {
  mut xs : [Cell; 2]
  xs[0].inner.x = 1
  return xs[0].inner.y
}
