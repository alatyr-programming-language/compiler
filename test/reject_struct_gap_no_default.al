## TYP-8 / spec Types §9.4 — a non-trailing field with NO default and NO provider is a GAP and must be
## rejected LOUD (never a silent wrong fill). Regression of the by-name gap guard: `c` has a default so
## it MUST be materialized (hi extends to index 2), which turns the omitted, non-defaulted `b` into a
## non-trailing gap → the build must FAIL. (A silent wrong binary would be the forbidden miscompile.)
G := struct { a : u64, b : u64, c : u64 = 7 }

main := fn() -> u64 {
  g := G(a = 1)          ## b omitted, no default, but c (defaulted) sits after it → gap, reject
  return g.a
}
