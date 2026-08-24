## Types §9.4 — the same composed `xs[i].cell.vals[j]` place with two roots whose type facts
## are not carried by a local array annotation: an inferred array local and a fixed-array parameter.
## `xs[0].cell.vals[1]` is written through the inferred local, then read through both forms.
Cell := struct { pad : u64, vals : [u64; 3] }
Row := struct { head : u64, cell : Cell, tail : u64 }
read_param := fn(xs : [Row; 2]) -> u64 {
  xs[0].cell.vals[1]
}
main := fn() -> u64 {
  mut xs := [Row(head = 1, cell = Cell(pad = 2, vals = [10, 20, 30]), tail = 3),
             Row(head = 4, cell = Cell(pad = 5, vals = [40, 50, 60]), tail = 6)]
  xs[0].cell.vals[1] = 7
  u64(xs[0].cell.vals[1] + read_param(xs))
}
