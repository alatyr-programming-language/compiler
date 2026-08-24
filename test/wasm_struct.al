Pt := struct { x : u64, y : u64 }
main := fn() -> u64 {
  p := Pt(x = 40, y = 2)
  return p.x + p.y
}
