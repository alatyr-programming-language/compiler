## Issue #304 — an element store through a field path with TWO owners must obey the leaf field's
## declared `Slice(T)`. `sema_direct_slice_field_elem_ty` resolved the owner with the already
## recursive `s3a_struct_span`, but a guard in front of it demanded a bare local, so the element
## type was UNKNOWN and any value was accepted. Measured on the parent: check and build both
## returned 0 and the string's address landed in a `u64` slot.
Leaf := struct { values : Slice(u64) }
Outer := struct { leaf : Leaf }

main := fn() -> u64 {
  mut values := [10, 20]
  mut outer := Outer(leaf = Leaf(values = values[0..2]))
  outer.leaf.values[0] = "text"
  0
}
