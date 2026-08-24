## P1-BYTES: a typed local tuple with a direct byte-array component uses the
## standard byte layout for construction, indexing, writes, and scalar neighbors.

main := fn() -> u64 {
  mut t : ([u8; 4], u64) = ([1, 2, 3, 4], 9)
  p0 := unchecked bitcast(usize, ptr(t.0[0]))
  p1 := unchecked bitcast(usize, ptr(t.0[1]))
  pt := unchecked bitcast(usize, ptr(t.1))
  t.0[2] = 42
  if unchecked (p1 - p0) != 1 { return 1 }
  if unchecked (pt - p0) != 8 { return 2 }
  if t.0[2] != 42 { return 3 }
  if t.0[3] != 4 { return 4 }
  if t.1 != 9 { return 5 }
  if size(t) != 16 { return 6 }
  if align(t) != 8 { return 7 }
  42
}
