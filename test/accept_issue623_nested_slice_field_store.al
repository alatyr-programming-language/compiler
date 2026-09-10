## Issue #623 — the same two-owner and three-owner field paths ending in a Slice(T) element store.
## The parser drop the fixture above measures is carrier-independent; this one keeps the Slice(T)
## classes sema must type for #304 reachable. Backend WRITE execution stays in a checked dead branch
## because a Slice(T) struct field still traps on AArch64, RISC-V64 and Wasm under #621; freezing
## those three exits here would record a defect the oracle then has to unlearn.
Leaf := struct { values : Slice(u64) }
Outer := struct { leaf : Leaf }
Flags := struct { bits : Slice(bool) }
Row := struct { flags : Flags }
Table := struct { row : Row }

main := fn() -> u64 {
  if false {
    mut values := [10, 20]
    mut outer := Outer(leaf = Leaf(values = values[0..2]))
    outer.leaf.values[0] = 42
    mut bits := [false, false]
    mut table := Table(row = Row(flags = Flags(bits = bits[0..2])))
    table.row.flags.bits[1] = true
  }
  42
}
