## Types §9.4 — a LOCAL struct with a `[Struct; N]` field (multi-word element). `field_words` now sizes
## the field as `N * struct_words(elem)` (was `N`, which under-reserved the frame block → SIGILL / silent
## corruption). Exercises: construction, `b.cells[i].m` READ, `b.cells[i].m = v` WRITE, NEIGHBOUR fields /
## elements not clobbered, and the WHOLE-STRUCT copy. `pad`/`tail` sit either side of the array so a
## mis-size shows; non-zero field values at shifted offsets catch a stride error. Returns 42 iff all pass.
Cell := struct { m : u64, n : u64 }
Box := struct { pad : u64, cells : [Cell; 3], tail : u64 }
main := fn() -> u64 {
  mut b := Box(pad = 7, cells = [Cell(m = 10, n = 11), Cell(m = 20, n = 21), Cell(m = 30, n = 31)], tail = 99)
  ## READ every element field at its pad+stride-shifted offset
  if b.pad != 7 { return 1 }
  if b.tail != 99 { return 2 }
  if b.cells[0].m != 10 { return 3 }
  if b.cells[0].n != 11 { return 4 }
  if b.cells[1].m != 20 { return 5 }
  if b.cells[1].n != 21 { return 6 }
  if b.cells[2].m != 30 { return 7 }
  if b.cells[2].n != 31 { return 8 }
  ## WRITE the middle element's m
  b.cells[1].m = 200
  if b.cells[1].m != 200 { return 9 }
  if b.cells[1].n != 21 { return 10 }   ## neighbour field in the SAME element intact
  if b.cells[0].m != 10 { return 11 }   ## prior element intact
  if b.cells[0].n != 11 { return 12 }
  if b.cells[2].m != 30 { return 13 }   ## next element intact
  if b.cells[2].n != 31 { return 14 }
  if b.pad != 7 { return 15 }           ## pad (before the array) intact
  if b.tail != 99 { return 16 }         ## tail (after the array) intact
  ## WHOLE-STRUCT copy carries the full [Struct; N] field
  mut c := b
  if c.pad != 7 { return 17 }
  if c.cells[0].m != 10 { return 18 }
  if c.cells[1].m != 200 { return 19 }
  if c.cells[2].m != 30 { return 20 }
  if c.cells[2].n != 31 { return 21 }
  if c.tail != 99 { return 22 }
  42
}
