## Functions §7.1 (heterogeneous packs): a comptime-variadic pack whose args are STRUCTS
## (multi-word) — each pack arg that is a bound variable keeps its own type, so the loop var `p` is a
## real `Pt` inside the body and `p.x` / `p.y` resolve. span(a, b) = (10+5) + (20+7) = 42.
Pt := struct { x : u64, y : u64 }

span := fn(args : ...) -> u64 {
  mut t := 0
  comptime for p in args {
    t = t + p.x + p.y
  }
  return t
}

main := fn() -> u64 {
  a := Pt(x = 10, y = 5)
  b := Pt(x = 20, y = 7)
  return span(a, b)
}
