P := struct { x : u64, y : u64 }
main := fn() -> u64 {
  mut ps := [P(x = 0, y = 0), P(x = 0, y = 0)]
  ps[0].x = 10
  ps[0].y = 11
  ps[1].x = 20
  ps[1].y = 1
  a := ps[0]
  b := ps[1]
  return a.x + a.y + b.x + b.y
}
