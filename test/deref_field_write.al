## e2e: a scalar FIELD WRITE THROUGH a pointer — `deref(p).field = v` where `p : ptr(mut Rec)`. The
## store dual of the `deref(p).f` READ. Was a Priority-1 SILENT MISCOMPILE: `stmt_starts` did not
## recognize `deref(p).field =` (a `deref` head has `(` at idx+1, not `.`), so the line parsed as a
## trailing RETURN expression and the store was dropped (and the whole module could emit empty); even
## when reached, lower's `field_slot` returned -1 for a `Deref` base → a store to `-0(%rbp)` (corrupting
## the saved frame pointer). Now the parser routes it to a `FieldPathAssign` and lower stores the field
## at `fi*8(ptr)` (the ascending pointee layout the read uses). Writes word 0 (`a`) AND word 1 (`b`)
## through the pointer param, then reads them back: 40 + 2 = 42.
Rec := struct { a : i64, b : i64 }
setab := fn(p : ptr(mut Rec)) {
  deref(p).a = 40
  deref(p).b = 2
}
main := fn() -> u64 {
  mut r := Rec(a = 0, b = 0)
  setab(ptr(mut r))
  u64(r.a + r.b)
}
