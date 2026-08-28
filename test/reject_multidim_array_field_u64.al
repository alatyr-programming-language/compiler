## I11 safety fence: a struct field whose element is itself an array is not yet a supported place.
## The parent compiled this read/write probe and returned a wrong value instead of stopping.
S := struct { data : [[u64; 2]; 2] }

main := fn() -> u64 {
  mut s := S(data = [[1, 2], [3, 4]])
  s.data[1][0] = 9
  if s.data[0][0] != 1 { return 1 }
  if s.data[0][1] != 2 { return 2 }
  if s.data[1][0] != 9 { return 3 }
  if s.data[1][1] != 4 { return 4 }
  42
}
