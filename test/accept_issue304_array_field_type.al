P := struct { f : u64, flag : bool }
S := struct { items : [P; 2] }
main := fn() -> u64 {
  mut s := S(items = [P(f = 1, flag = false), P(f = 2, flag = false)])
  s.items[0].f = 40
  s.items[0].flag = true
  return s.items[0].f + if s.items[0].flag { 2 } else { 0 }
}
