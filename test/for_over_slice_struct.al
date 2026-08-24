Pt := struct { x : u64, y : u64 }
main := fn() -> u64 {
  ps : [Pt; 4] = [Pt(x = 99, y = 0), Pt(x = 20, y = 1), Pt(x = 3, y = 2), Pt(x = 19, y = 3)]
  s := ps[1..4]
  mut sum : u64 = 0
  for p in s { sum = sum + p.x }
  return sum
}
