Inner := struct { v : u64 }
Outer := struct { i : Inner, k : u64 }
main := fn() -> u64 {
  mut o := Outer(i = Inner(v = 1), k = 2)
  o.i.v = 40
  return o.i.v + o.k
}
