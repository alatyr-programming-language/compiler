## e2e (aggregate delivered into a NESTED STRUCT FIELD sink — both from an `if` branch and covered for a
## literal/var). `o.inner = if c { Rec(12,30) } else {…}` where `inner : Rec` is a 2-word struct field.
## The local-base `FieldAssign` handled str + enum multi-word fields but dropped a NESTED STRUCT field to
## a scalar word-0-only store (the field's other words kept STALE) — a Priority-1 silent miscompile. Now
## a multi-word struct field delivers ALL its words (a struct literal / an `if`/`match` value / a struct
## var). Here the `if` value writes both words; `o.inner.a + o.inner.b` = `12 + 30` -> 42.
Rec := struct { a : i64, b : i64 }
Outer := struct { inner : Rec, tag : i64 }
main := fn() -> u64 {
  c := true
  mut o := Outer(inner = Rec(a = 0, b = 0), tag = 7)
  o.inner = if c { Rec(a = 12, b = 30) } else { Rec(a = 0, b = 0) }
  return u64(o.inner.a + o.inner.b)
}
