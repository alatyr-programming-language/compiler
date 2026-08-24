## fmt round-trip of forms that formerly failed loud / rendered lossily: a MULTI-PAYLOAD enum variant
## declaration (`Pair(u64, u64)` — the FieldDecl keeps only arity + first type, so fmt recovers the
## whole `(…)` group verbatim from source), the boolean short-circuit operators `and`/`or` + the prefix
## `not` (parser op bytes 40/41/42, not the `and`/`or` token kinds), and a string literal with an ESCAPE
## (`"\t"` — the stored StrLit length is the DECODED count, so fmt renders the raw source span). Formats
## idempotently and runs to 42.
E := enum { Pair(u64, u64), None }
main := fn() -> u64 {
  p := E.Pair(30, 12)
  esc := "\t"
  cond := (1 < 2 and 3 > 2) or not (5 == 6)
  r := match p {
    E.Pair(a, b) => a + b
    _ => 0
  }
  if cond and esc == "\t" {
    return r
  }
  return 0
}
