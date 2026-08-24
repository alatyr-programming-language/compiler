## §4/§8: NESTED mixed-kind tuple element access `t.N.M` (parsed `Index(Index(t, N), M)`). The outer
## tuple is MIXED (a scalar component next to a wider nested-tuple component), so component 1 sits at a
## cumulative word offset recorded in the per-component layout table (`tcomps`); `t.1.0`/`t.1.1` read
## words 0/1 WITHIN that nested component. Was fail-loud (uniform-stride math on `(20, (14, 8))` would
## mis-address the wider component). Values chosen so ONLY a correct nested read totals 42:
## t.0 + t.1.0 + t.1.1 = 20 + 14 + 8 = 42 (a wrong offset re-reads t.0=20 or a filler → not 42).
main := fn() -> u64 {
  t := (20, (14, 8))
  return t.0 + t.1.0 + t.1.1
}
