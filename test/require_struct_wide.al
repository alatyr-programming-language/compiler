Wide := struct { a : u64, b : u64, c : u64, d : u64, e : u64, f : u64, g : u64, h : u64 }
within := fn(p : Wide) -> bool { return p.a != 0 }
tail := fn(p : Wide) -> u64 { return p.h }
Checked := Wide.require(within)

main := fn() -> u64 {
  x := Checked(Wide(a = 1, b = 2, c = 3, d = 4, e = 5, f = 6, g = 7, h = 42))
  if x.h != 42 { return 1 }
  return tail(Checked(Wide(a = 1, b = 2, c = 3, d = 4, e = 5, f = 6, g = 7, h = 42)))
}
