Inner := struct { v : u64 }
Outer := struct { i : Inner, k : u64 }
main := fn() -> u64 {
  o := Outer(i = Inner(v = 40), k = 2)
  return o.i.v + o.k
}
