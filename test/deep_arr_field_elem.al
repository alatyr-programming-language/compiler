## Types §9.4 — an array element, then a nested struct field, then an inline array field:
## `xs[i].cell.vals[j]`. The resolver must compose the element base, both field offsets,
## and the inner array index. The non-zero pads catch a dropped intermediate field offset.
Cell := struct { pad : u64, vals : [u64; 3] }
Row := struct { head : u64, cell : Cell, tail : u64 }
main := fn() -> u64 {
  mut xs : [Row; 2]
  xs[0] = Row(head = 1, cell = Cell(pad = 2, vals = [10, 20, 30]), tail = 3)
  xs[1] = Row(head = 4, cell = Cell(pad = 5, vals = [40, 50, 60]), tail = 6)
  xs[0].cell.vals[1] = 7
  xs[1].cell.vals[2] = 11
  u64(xs[0].cell.vals[1]
    + xs[1].cell.vals[2]
    + xs[0].cell.vals[0]
    + xs[1].cell.vals[1]
    + xs[0].cell.pad
    + xs[1].tail)
}
