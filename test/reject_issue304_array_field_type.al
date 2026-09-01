P := struct { f : u64, keep : u64 }
S := struct { items : [P; 2] }
main := fn() -> u64 {
  mut s := S(items = [P(f = 1, keep = 2), P(f = 3, keep = 4)])
  s.items[0].f = "text"
  return s.items[0].f
}
