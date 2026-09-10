## Issue #623 — the recovered statement form must still obey the write-permission rule.
## `outer` is bound without `mut`, so the element store through it is not a legal write. On the
## parent the whole line was not a statement at all, so both `check` and the build exited 0 and the
## store was silently discarded: an unwritable place accepted with no diagnostic. Both entry points
## must now refuse it, and the refusal must name the line the user wrote.
Leaf := struct { values : Slice(u64) }
Outer := struct { leaf : Leaf }

main := fn() -> u64 {
  mut values := [10, 20]
  outer := Outer(leaf = Leaf(values = values[0..2]))
  outer.leaf.values[0] = 42
  return 42
}
