## P1-CLAYOUT S3(e): an ordinary standard-byte-layout struct crosses a
## by-value parameter and return boundary on every supported backend.

S := struct { data : [u8; 4], tail : u16 }

take := fn(s : S) -> u64 {
  return u64(s.data[0]) + u64(s.data[1]) + u64(s.data[2]) + u64(s.data[3]) + u64(s.tail)
}

round := fn(s : S) -> S {
  return s
}

main := fn() -> u64 {
  source := S(data = [1, 2, 3, 4], tail = 9)
  got := round(source)
  if take(got) != 19 { return 1 }
  if got.data[0] != 1 { return 2 }
  if got.data[3] != 4 { return 3 }
  if got.tail != 9 { return 4 }
  42
}
