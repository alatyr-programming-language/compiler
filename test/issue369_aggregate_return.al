## Issue #369 / Types §§3.4, 4.4 and Memory §5.9 — an equal-width aggregate bitcast used
## directly as a struct return value preserves every source word in both verification modes.
## Distinct non-zero words make a zero-result or word-0-only return observable.
A1 := struct { a : u64 }
B1 := struct { x : u64 }
A2 := struct { a : u64, b : u64 }
B2 := struct { x : u64, y : u64 }
A3 := struct { a : u64, b : u64, c : u64 }
B3 := struct { x : u64, y : u64, z : u64 }

plain1 := fn(a : A1) -> B1 {
  return bitcast(B1, a)
}

raw1 := fn(a : A1) -> B1 {
  return unchecked bitcast(B1, a)
}

plain2 := fn(a : A2) -> B2 {
  return bitcast(B2, a)
}

raw2 := fn(a : A2) -> B2 {
  return unchecked bitcast(B2, a)
}

plain3 := fn(a : A3) -> B3 {
  return bitcast(B3, a)
}

raw3 := fn(a : A3) -> B3 {
  return unchecked bitcast(B3, a)
}

main := fn() -> u64 {
  p1 := plain1(A1(a = 42))
  if p1.x != 42 { return 1 }
  r1 := raw1(A1(a = 42))
  if r1.x != 42 { return 2 }

  p2 := plain2(A2(a = 40, b = 2))
  if p2.x + p2.y != 42 { return 3 }
  r2 := raw2(A2(a = 40, b = 2))
  if r2.x + r2.y != 42 { return 4 }

  p3 := plain3(A3(a = 10, b = 20, c = 12))
  if p3.x + p3.y + p3.z != 42 { return 5 }
  r3 := raw3(A3(a = 10, b = 20, c = 12))
  if r3.x + r3.y + r3.z != 42 { return 6 }
  return 42
}
