P := struct { x : u64, y : u64 }
main := fn() -> u64 {
  mut ps : [P; 2]
  ps[0].x = 42
  q := ps[0]
  return q.x
}
