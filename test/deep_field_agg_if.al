## e2e (DEEP-CHAIN field whole-assign delivered from an `if` VALUE). `o.mid.inner = if c { Rec(…) }
## else {…}` — a 2-hop field path (`FieldPathAssign`) whose multi-word struct final field is written
## from an if-EXPRESSION via the `emit_val_if_to_local` branch primitive (both words delivered). The
## deep-chain dual of the single-hop branch-into-field case (`agg_from_branch_field`). Exits 42.
Rec := struct { a : i64, b : i64 }
Mid := struct { inner : Rec, x : i64 }
Outer := struct { mid : Mid, tag : i64 }
main := fn() -> u64 {
  c := true
  mut o : Outer = Outer(mid = Mid(inner = Rec(a = 0, b = 0), x = 0), tag = 7)
  o.mid.inner = if c { Rec(a = 12, b = 30) } else { Rec(a = 0, b = 0) }
  return u64(o.mid.inner.a + o.mid.inner.b)
}
