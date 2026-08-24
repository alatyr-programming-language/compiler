S10 := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64, i : u64, j : u64 }

mk := fn(a : u64, b : u64, c : u64, d : u64, e : u64, f : u64) -> S10 {
  v := S10(a = a, b = b, c = c, d = d, e = e, f = f, g = 0, h = 0, i = 0, j = 0)
  return v
}

main := fn() -> u64 {
  s := mk(1, 2, 3, 4, 5, 27)
  return s.a + s.b + s.c + s.d + s.e + s.f
}
