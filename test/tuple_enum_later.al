## Regression (I11): matching an ENUM tuple component that is NOT the first component (`match t.1`
## where the enum sits after a scalar). The scrutinee's enum type is recovered from the mixed-tuple
## `tcomps` in try_index_enum_scrut, so the variant discriminants resolve — was a SILENT MISCOMPILE
## (the enum type didn't resolve, so both arms compared against discriminant 0 → wrong dispatch → 255).
## Covers a LOCAL value-match and a by-ref PARAM statement-match. loc(38) + pick(0+4) = 42.
Color := enum { R, G(u64) }

pick := fn(t : (u64, Color)) -> u64 {
  match t.1 { Color::R => { return t.0 } Color::G(n) => { return t.0 + n } }
}

main := fn() -> u64 {
  t := (2, Color.G(38))
  loc := match t.1 { Color::R => { 0 } Color::G(n) => { n } }
  u := (0, Color.G(4))
  return loc + pick(u)
}
