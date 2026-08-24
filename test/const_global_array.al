## e2e (§4 — a CONST, non-`mut` module-global ARRAY used as a lookup table). Unlike a scalar/struct
## const (compile-time inlined), a const ARRAY needs `.data` storage because `TAB[i]` is a runtime-
## indexed read: `global_needs_storage` now materializes it, `emit_global_label` resolves its label,
## and the Index read falls back to `const_array_value`. Exercises indexed reads at several positions
## and an accumulating loop. `src/`+`lib/` declare no const global arrays (they use fns/spans), so this
## stays fixpoint-neutral.
TAB := [10, 20, 12]
PRIMES := [2, 3, 5, 7, 11]

main := fn() -> u64 {
  a := TAB[0] + TAB[1] + TAB[2]      ## 10 + 20 + 12 = 42 (direct indexed reads)
  mut s : u64 = 0
  mut i : usize = 0
  while i < 5 { s = s + PRIMES[i]; i = i + 1 }   ## 2+3+5+7+11 = 28
  if a == 42 and s == 28 { return 42 }
  1
}
