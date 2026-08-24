## Types §9.4 — deep field-then-index place rooted at a mutable global array:
## TAB[i].cell.vals[j]. The global's ascending .data stride and both field offsets must compose.
Cell := struct { pad : u64, vals : [u64; 3] }
Row := struct { head : u64, cell : Cell, tail : u64 }
mut TAB := [Row(head = 1, cell = Cell(pad = 2, vals = [10, 20, 30]), tail = 3),
            Row(head = 4, cell = Cell(pad = 5, vals = [40, 50, 60]), tail = 6)]
main := fn() -> u64 {
  TAB[0].cell.vals[1] = 7
  TAB[1].cell.vals[2] = 11
  u64(TAB[0].cell.vals[1]
    + TAB[1].cell.vals[2]
    + TAB[0].cell.vals[0]
    + TAB[1].cell.vals[1]
    + TAB[0].cell.pad
    + TAB[1].cell.pad)
}
