## P1-BYTES: an explicitly typed byte array is packed by byte, not by word.
## The pointer deltas, range-slice backing, and byte write all observe the same contiguous storage.
main := fn() -> u64 {
  mut xs : [u8; 4] = [11, 22, 33, 44]
  p0 := unchecked bitcast(usize, ptr(xs[0]))
  p1 := unchecked bitcast(usize, ptr(xs[1]))
  p3 := unchecked bitcast(usize, ptr(xs[3]))
  if unchecked (p1 - p0) != 1 { return 1 }
  if unchecked (p3 - p0) != 3 { return 2 }

  view := xs[1..4]
  if view.len != 3 { return 3 }
  if view[0] != 22 { return 4 }
  if view[2] != 44 { return 5 }
  view[1] = 77
  if xs[2] != 77 { return 6 }
  if xs[0] != 11 { return 7 }
  if xs[3] != 44 { return 8 }
  42
}
