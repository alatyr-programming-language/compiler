Pt := struct { x : u64, y : u64 }
takes_pt := fn(p : Pt) -> u64 { p.x + p.y }
takes_u64 := fn(x : u64) -> u64 { x }
main := fn() -> u64 {
  comptime if compiles(takes_pt(1)) { return 1 } else { }
  comptime if compiles(takes_u64(Pt(x = 1, y = 2))) { return 2 } else { }
  comptime if compiles(Pt(x = 1, y = 2).z) { return 3 } else { }
  42
}
