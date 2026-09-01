## AXIS coverage for #306: field-layout eightbyte x operation wide-then-narrow x read/write.
## The changed byte field and its non-zero wide neighbour are both checked before and after the write.
WideFirst := struct { wide : u64, narrow : u8 }
NarrowFirst := struct { narrow : u8, wide : u64 }

main := fn() -> u64 {
  mut wide_first := WideFirst(wide = 700, narrow = 3)
  if wide_first.narrow != 3 { return 1 }
  wide_first.narrow = 9
  if wide_first.narrow != 9 { return 2 }
  if wide_first.wide != 700 { return 3 }

  mut narrow_first := NarrowFirst(narrow = 5, wide = 701)
  if narrow_first.wide != 701 { return 4 }
  narrow_first.narrow = 11
  if narrow_first.narrow != 11 { return 5 }
  if narrow_first.wide != 701 { return 6 }
  42
}
