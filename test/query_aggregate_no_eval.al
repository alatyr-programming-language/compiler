Pt := struct { x : u64, y : u64 }
takes_pt := fn(p : Pt) -> u64 { p.x + p.y }
side := fn() -> Pt { panic("aggregate query operand evaluated") }
main := fn() -> u64 {
  comptime if compiles(takes_pt(side())) { return 42 } else { return 1 }
}
