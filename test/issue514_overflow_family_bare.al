## issue #514 control — the three overflow-policy prefixes that were ALREADY in the ambient trigger
## list (`wrapping_`/`saturating_`/`overflowing_`, Concurrency §6.3), reached bare. Like its
## `checked_` sibling this file NEVER SPELLS a base result-type name, so nothing but the
## overflow-prefix trigger itself can pull its prelude. These answered 42 on the parent too; the row exists
## so completing the list for `checked_` cannot regress them, and so the family — not one prefix —
## is what the fix covers.
##
## `overflowing_*` returns a `(T, bool)` pair, so BOTH components are read back on BOTH paths: a name that
## merely resolves is not evidence that the pair is laid out and loaded correctly. The operands are
## chosen so all four backends agree — `overflowing_mul` derives its flag from a high-word helper
## with no wasm arm, so only `a == 0` (flag false) and a genuinely overflowing multiply (flag true)
## are portable; the arch-dependent middle ground belongs to a different issue.
main := fn() -> u64 {
  a : u64 = 41
  z : u64 = 0
  mx : u64 = 18446744073709551615
  if wrapping_add(a, 1) != 42 { return 1 }
  if wrapping_add(mx, 2) != 1 { return 2 }
  if saturating_sub(a, 40) != 1 { return 3 }
  if saturating_sub(a, 42) != 0 { return 4 }
  if saturating_add(mx, 5) != mx { return 5 }
  p := overflowing_add(a, 1)
  if p.0 != 42 { return 6 }
  if p.1 { return 7 }
  q := overflowing_mul(z, 7)
  if q.0 != 0 { return 8 }
  if q.1 { return 9 }
  t := overflowing_mul(mx, 3)
  if t.0 != 18446744073709551613 { return 10 }
  if t.1 == false { return 11 }
  42
}
