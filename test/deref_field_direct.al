## e2e: a DIRECT `deref(<struct>.<field>).f` field read through a pointer-typed struct FIELD, with NO
## intermediate `n := box.inner` binding — the idiomatic linked-list / tree walk spelled inline.
## `inner` is a `ptr(Pair)` field; `deref(box.inner).a` must resolve the pointee's field through the
## field's pointer value. Previously only the bound form (`n := box.inner; deref(n).a`) lowered (the
## field RHS was recognized by `collect_slots`); the inline `deref(box.inner).a` fell to the scalar/
## `field_slot` default and read 0. `deref_field_ptrstruct_span` now resolves the pointee (the read dual
## of the `x := deref(o.p)` binding path). Exercises BOTH a non-zero OUTER field offset (`inner` is the
## 2nd field of Box) AND a non-zero INNER field offset (`.b` is the 2nd field of Pair). 30+10+2=42.
Pair := struct { a : u64, b : u64 }
Box := struct { tag : u64, inner : ptr(Pair) }
main := fn() -> u64 {
  mut p := Pair(a = 10, b = 2)
  bx := Box(tag = 1, inner = ptr(p))
  ## inner field offset 0 (`.a`), outer field offset 1 (`inner`)
  x := deref(bx.inner).a
  ## inner field offset 1 (`.b`), through the same field-deref path
  y := deref(bx.inner).b
  30 + x + y
}
