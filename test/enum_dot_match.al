## e2e: a match pattern spelled with the DOT-qualified form `E.Variant` (grammar variant-pat ::=
## type-expr "." ident) — the same way the variant is CONSTRUCTED (`E.Pt(30, 12)`). Formerly only the
## `::`/bare spellings resolved; a `.`-spelled pattern left the tail unconsumed, so the `=>` skip ate
## the `.` and desynced (the variant resolved to -1 → no arm matched). Now the statement- AND
## expression-match arm parsers consume `.Variant` like a `::` segment. A nullary arm (`E.Red`) and a
## payload-binding arm (`E.Pt(x, y)`) both via the dot spelling; Pt(30, 12) → 30 + 12 = 42.
E := enum { Red, Pt(u64, u64) }
main := fn() -> u64 {
  c := E.Pt(30, 12)
  match c {
    E.Red => { return 1 }
    E.Pt(x, y) => { return x + y }
  }
}
