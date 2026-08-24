Pt := struct { x : u64, y : u64 }
takes_pt := fn(p : Pt) -> u64 { p.x + p.y }
main := fn() -> u64 {
  comptime if compiles(takes_pt(Pt(x = 40, y = 2))) { return 42 } else { return 1 }
}
