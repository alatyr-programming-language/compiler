## Issue #304 — THREE owners, so the fix is the owner recursion and not one extra hop. The owner
## resolver walks `Table -> Row -> Flags` before the leaf `Slice(u64)` annotation is read. The
## parent accepted this with check/build rc 0 exactly as it accepted the two-owner form.
Flags := struct { bits : Slice(u64) }
Row := struct { flags : Flags }
Table := struct { row : Row }

main := fn() -> u64 {
  mut bits := [10, 20]
  mut table := Table(row = Row(flags = Flags(bits = bits[0..2])))
  table.row.flags.bits[1] = "text"
  0
}
