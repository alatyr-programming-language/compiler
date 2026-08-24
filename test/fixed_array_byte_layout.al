## BYTES: explicit local byte arrays expose byte-precise size/align queries.
## Their storage is packed by byte stride, so size([u8; N]) is N and align is 1.
main := fn() -> u64 {
  mut us : [u8; 4] = [1, 2, 3, 4]
  mut is : [i8; 3] = [-1, 2, 3]
  mut bs : [bits8; 2] = [5, 6]
  if size(us) != 4 { return 1 }
  if align(us) != 1 { return 2 }
  if size(is) != 3 { return 3 }
  if align(is) != 1 { return 4 }
  if size(bs) != 2 { return 5 }
  if align(bs) != 1 { return 6 }
  42
}
