Pt := struct { x : u64, y : u64 }
sum := fn(p : Pt) -> u64 { return p.x + p.y }
main := fn() -> u64 {
  q := Pt(x = 40, y = 2)
  return sum(q)
}
