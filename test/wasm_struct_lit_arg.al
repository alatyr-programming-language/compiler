Pt := struct { x : u64, y : u64 }
sum := fn(p : Pt) -> u64 { p.x + p.y }
main := fn() -> u64 { sum(Pt(x = 40, y = 2)) }
