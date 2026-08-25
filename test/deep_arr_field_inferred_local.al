## Types §9.4 — an inferred homogeneous struct-array local as the root of a composed scalar place.
## Runtime outer and inner indices, a write followed by reads, and non-zero Row/Cell offsets keep the
## root stride and both intermediate field offsets observable. Other roots and aggregate leaves stay out.
## Failure-first on parent 07492f4: x86_64=25, AArch64=133, RV64=133, WAT=134.
Cell := struct { pad : u64, vals : [u64; 3] }
Row := struct { head : u64, cell : Cell, tail : u64 }

main := fn() -> u64 {
  mut xs := [Row(head = 1, cell = Cell(pad = 2, vals = [10, 20, 30]), tail = 3),
             Row(head = 4, cell = Cell(pad = 5, vals = [40, 50, 60]), tail = 6)]
  mut i : u64 = 1
  mut j : u64 = 2
  if xs[i].head != 4 { return 1 }
  if xs[i].cell.pad != 5 { return 2 }
  if xs[i].cell.vals[0] != 40 { return 3 }
  if xs[i].cell.vals[1] != 50 { return 4 }
  if xs[i].cell.vals[2] != 60 { return 5 }
  if xs[0].cell.vals[2] != 30 { return 6 }
  xs[i].cell.vals[j] = 7
  after := xs[i].cell.vals[j]
  if after != 7 { return 7 }
  if xs[1].head != 4 { return 8 }
  if xs[1].cell.pad != 5 { return 9 }
  if xs[1].cell.vals[0] != 40 { return 10 }
  if xs[1].cell.vals[1] != 50 { return 11 }
  if xs[1].cell.vals[2] != 7 { return 12 }
  if xs[0].head != 1 { return 13 }
  if xs[0].cell.pad != 2 { return 14 }
  if xs[0].cell.vals[0] != 10 { return 15 }
  if xs[0].cell.vals[1] != 20 { return 16 }
  if xs[0].cell.vals[2] != 30 { return 17 }
  25
}
