## Types §9.4 conservative frontier: deeper local-array element leaf paths still fail loud, not silently initialize.
Leaf := struct { x : u64, y : u64 }
Cell := struct { inner : Leaf, z : u64 }
main := fn() -> u64 {
  mut xs : [Cell; 2]
  xs[0].inner.x = 42
  return xs[0].inner.x
}
