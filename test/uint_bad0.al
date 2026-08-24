## e2e — TYP-10 ADMISSIBILITY (Types §7 / TYP-10): `uint(N)` admits only a POSITIVE multiple of
## 64. `uint(0)` folds the array length `N/64` to ZERO — not a valid fixed-array length — and
## must FAIL LOUD at compile time (the slice-A positivity guard, verified here against the
## SHIPPED prelude recipe via ambient injection, no local decl). build_reject: non-zero build rc.
main := fn() -> u64 {
  x := uint(0)(words = [0])
  x.words[0]
}
