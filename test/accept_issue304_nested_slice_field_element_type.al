## Issue #304 controls — the valid two-owner and three-owner nested `Slice(T)` element stores that
## the new owner recursion must keep accepting: an integer into `Slice(u64)` and a boolean into
## `Slice(bool)`, each reached through a chain of declared struct fields.
##
## The stores stay in a checked dead branch on purpose. `sema` walks an `if false` block, so this
## file proves acceptance on all four backends, while a LIVE nested `Slice(T)` field access still
## traps on AArch64, RISC-V64 and Wasm under the independent #621 — and the per-file corpus row
## would record those exits, freezing a defect the oracle then has to unlearn. The executing proof
## for this statement form is the fixed-array carrier in accept_issue623_nested_array_field_store,
## whose three cross-backend runners this change leaves untouched.
##
## Every local is bound before the first indexed store: on Wasm an indexed write followed by a
## LATER structural local exits 134 on the parent too (#631), and that unrelated defect must not be
## smuggled into this row.
Leaf := struct { values : Slice(u64) }
Outer := struct { leaf : Leaf }
Flags := struct { bits : Slice(bool) }
Row := struct { flags : Flags }
Table := struct { row : Row }

main := fn() -> u64 {
  if false {
    mut values := [10, 20]
    mut bits := [false, false]
    mut outer := Outer(leaf = Leaf(values = values[0..2]))
    mut table := Table(row = Row(flags = Flags(bits = bits[0..2])))
    outer.leaf.values[0] = 42
    table.row.flags.bits[1] = true
  }
  42
}
