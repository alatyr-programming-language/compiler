Pt := struct {
  x : u64,
  y : u64,
}
Opt := enum {
  None,
  Some(u64),
}
main := fn() -> u64 {
  p := Pt(x = 40, y = 2)
  o := Opt.Some(p.x)
  return match o { Some(v) => v + p.y, None => 0 }
}
