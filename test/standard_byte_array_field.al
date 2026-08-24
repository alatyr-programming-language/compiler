## BYTES: an ordinary struct with a direct byte-array field uses the shared standard-layout
## calculator and the byte-precise aggregate consumers.
S := struct { data : [u8; 4], tail : u16 }

sum := fn(s : S) -> u64 {
  return u64(s.data[0]) + u64(s.data[1]) + u64(s.data[2]) + u64(s.data[3]) + u64(s.tail)
}

main := fn() -> u64 {
  mut s := S(data = [1, 2, 3, 4], tail = 9)
  copy := s
  p0 := unchecked bitcast(usize, ptr(s.data[0]))
  p1 := unchecked bitcast(usize, ptr(s.data[1]))
  pt := unchecked bitcast(usize, ptr(s.tail))
  s.data[2] = 42
  s.tail = 300
  if p1 - p0 != 1 { return 1 }
  if pt - p0 != 4 { return 2 }
  if s.data[0] != 1 { return 3 }
  if s.data[2] != 42 { return 4 }
  if s.tail != 300 { return 5 }
  if copy.data[3] != 4 { return 6 }
  if copy.tail != 9 { return 7 }
  if sum(s) != 349 { return 8 }
  if size(S) != 6 { return 9 }
  if align(S) != 2 { return 10 }
  42
}
