P := struct { x : u64, y : u64 }
main := fn() -> u64 {
  mut ps := [P(x = 0, y = 0), P(x = 0, y = 0)]
  ps[0].x = 20
  ps[0].y = 22
  q := ps[0]
  return q.x + q.y
}
