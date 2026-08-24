P := struct { x : u64, y : u64 }
main := fn() -> u64 {
  mut ps : [P; 2]
  i := 0
  ps[i].x = 42
  return ps[0].x
}
