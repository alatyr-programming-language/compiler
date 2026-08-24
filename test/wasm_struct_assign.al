Pt := struct { x : u64, y : u64 }
main := fn() -> u64 {
  p := Pt(x = 0, y = 0)
  p.x = 40
  p.y = 2
  return p.x + p.y
}
