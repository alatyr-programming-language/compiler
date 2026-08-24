P := struct { x : u64, y : u64 }
main := fn() -> u64 {
  mut ps : [P; 2]
  ps[0].x = 42
  ps[0].y = 0
  return ps[1].x
}
