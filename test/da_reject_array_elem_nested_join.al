## Types §9.4: branch join keeps a nested leaf unreadied unless every continuing branch writes it.
Leaf := struct { x : u64, y : u64 }
Cell := struct { inner : Leaf, z : u64 }
main := fn() -> u64 {
  mut xs : [Cell; 2]
  if true { xs[0].inner.x = 1 } else { xs[0].inner.y = 2 }
  return xs[0].inner.x
}
