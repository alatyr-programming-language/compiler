## Types §4.6 / TYP-6 SOUNDNESS — a builtin scalar conversion `T(v)` (`u64(...)`) applied to a user
## AGGREGATE operand (a struct) with NO in-scope `@convert fn(Rec) -> u64` MUST fail loud, never
## silently read the struct's word 0 as if it were a scalar (the forbidden silent miscompile). There
## is deliberately no `@convert` here — the build must be REJECTED (a non-zero rc), not emit a binary
## that returns `rec.a`.
Rec := struct { a : i64, b : i64 }
main := fn() -> u64 {
  rec := Rec(a = 40, b = 2)
  return u64(rec)
}
