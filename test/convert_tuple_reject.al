## Types §4.6 / TYP-6 SOUNDNESS — a builtin scalar conversion `T(v)` (`u64(...)`) applied to a TUPLE
## operand with NO in-scope `@convert fn((i64,i64)) -> u64` MUST fail loud. A tuple is an N-word
## aggregate (built as an `ArrayLit`, ek==5), which `expr_type_span` reports as 0/0 — so the named
## struct/enum gate misses it and the scalar lattice would silently read the tuple's WORD 0
## (`u64((40, 2))` → 40, the forbidden silent miscompile). The build must be REJECTED (non-zero rc).
main := fn() -> u64 {
  t := (40, 2)
  return u64(t)
}
