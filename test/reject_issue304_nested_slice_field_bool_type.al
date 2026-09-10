## Issue #304 — the boolean half of the same two-owner element store. `bool` into `Slice(u64)` is
## not a widening under Types §4.2's lattice; the name form already refuses it, and the parent
## accepted it here with check/build rc 0, storing 1 in a slot the program's own type calls an
## integer.
Leaf := struct { values : Slice(u64) }
Outer := struct { leaf : Leaf }

main := fn() -> u64 {
  mut values := [10, 20]
  mut outer := Outer(leaf = Leaf(values = values[0..2]))
  outer.leaf.values[0] = true
  0
}
