Pt := struct { x : u64, y : u64 }
mut G := Pt(x = 40, y = 2)
main := fn() -> u64 { G.x + G.y }
