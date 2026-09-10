## Issue #304 — the aggregate-into-scalar refusal, which #304's own table records as WORKING for a
## direct place, did not survive the two-owner path either: the parent accepted a struct value into
## a `Slice(u64)` element with check/build rc 0. This is the class the issue calls "the useful
## signal", so it is pinned separately from the scalar and boolean rows.
Leaf := struct { values : Slice(u64) }
Outer := struct { leaf : Leaf }
Point := struct { x : u64, y : u64 }

main := fn() -> u64 {
  mut values := [10, 20]
  mut outer := Outer(leaf = Leaf(values = values[0..2]))
  outer.leaf.values[0] = Point(x = 7, y = 9)
  0
}
