Pt := struct { x : u64, y : u64 }
make := fn() -> Pt { return Pt(x = 40, y = 2) }
main := fn() -> u64 {
  p := make()
  return p.x + p.y
}
