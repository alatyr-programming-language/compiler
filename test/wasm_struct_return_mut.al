Pt := struct { x : u64, y : u64 }
make := fn() -> Pt { return Pt(x = 40, y = 1) }
main := fn() -> u64 {
  mut p := make()
  p.y = 2
  return p.x + p.y
}
