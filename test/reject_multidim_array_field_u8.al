## I11 safety fence: the same unsupported field shape must not depend on element width.
S := struct { data : [[u8; 2]; 2] }

main := fn() -> u64 {
  mut s := S(data = [[1, 2], [3, 4]])
  s.data[1][0] = 9
  if u64(s.data[0][0]) != 1 { return 1 }
  if u64(s.data[0][1]) != 2 { return 2 }
  if u64(s.data[1][0]) != 9 { return 3 }
  if u64(s.data[1][1]) != 4 { return 4 }
  42
}
