Pt := struct { x : u64, y : u64 }
Box := enum { Full(Pt), Empty }
mk := fn(b : bool) -> Box {
  if b { return Box.Full(Pt(x = 40, y = 2)) }
  Box.Empty
}
main := fn() -> u64 {
  r := mk(true)
  match r {
    Box::Full(v) => { v.x + v.y }
    Box::Empty => { 1 }
  }
}
