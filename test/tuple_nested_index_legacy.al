## §4/§8: NESTED mixed-kind tuple element access `t.1.0`/`t.1.1` (an Index whose base is itself an Index
## into a MIXED tuple). Component 1 (the nested tuple `(1, 1)`) lives at a cumulative word offset recorded
## in the per-component layout table; its word M is read at `component-base + M*8`. Was fail-loud (a
## uniform-stride read on `(40, (1, 1))` mis-addressed the wider component → 81). A uniform array-of-arrays
## `m[i][j]` (no tcomps) uses the eek-5 array-of-tuples path; `t.1.x` (a struct component field) the Field path.
main := fn() -> u64 {
  t := (40, (1, 1))
  return t.0 + t.1.0 + t.1.1
}
