## fmt — NESTED aggregate literals round-trip (§5 tooling): a struct literal whose field values are
## themselves struct literals `Outer(a = Inner(x = 1, y = 2), b = Inner(x = 3, y = 4))`, alongside an
## array literal. The by-name field recovery + comma joining nest correctly. Sum of all fields +
## array = 1+2+3+4 + 10+20+12 = 52.
Inner := struct { x : u64, y : u64 }
Outer := struct { a : Inner, b : Inner }
main := fn() -> u64 {
  o := Outer(a = Inner(x = 1, y = 2), b = Inner(x = 3, y = 4))
  arr : [u64; 3] = [10, 20, 12]
  return o.a.x + o.a.y + o.b.x + o.b.y + arr[0] + arr[1] + arr[2]
}
