## e2e — Verification §: an `unchecked (…)` SCOPE changes the OVERFLOW-CHECKING MODE of the
## expression it wraps, never its TYPE. So a `u64` value that reaches an ordering comparison through
## an `unchecked` wrapper must still be compared with the UNSIGNED setcc.
##
## What was silently wrong: `expr_type_span` has no `Unchecked` arm and `infer_local_scalar_type` had
## none either, so `s := unchecked (w + d)` bound `s` UNTYPED. `is_unsigned_expr` could then not prove
## `s` unsigned, the comparison fell back to the always-SIGNED `setl`, and a wrapped `u64` sum whose
## word sits above 2^63 compared as a NEGATIVE number: `s < w` with s = 0 and w = 2^64-6 answered
## FALSE. Annotating the binding (`s : u64 = …`) or dropping the `unchecked` both gave the right
## answer — the signature of a dropped fact, not of a wrong rule.
##
## Both directions are proof-only: the fix peels `unchecked` and recurses through unsigned ARITHMETIC,
## so an operand is only ever moved signed -> unsigned when it is PROVEN unsigned. The always-signed
## default (which the compiler's own `isize` comparisons depend on) is untouched — `sm` below is the
## control: two negative-going `i64`s must still compare SIGNED.
##
## 1 + 2 + 4 + 8 + 16 + 8 + 3 = 42.
main := fn() -> u64 {
  w : u64 = 18446744073709551610      ## 2^64 - 6
  d : u64 = 6
  s := unchecked (w + d)              ## wraps to 0 — an UNTYPED binding through `unchecked`
  mut acc : u64 = 0
  if s < w { acc = acc + 1 }          ## 0 < 2^64-6 unsigned            -> +1
  if w > s { acc = acc + 2 }          ## reversed operand order         -> +2
  if s <= w { acc = acc + 4 }         ## `<=`                           -> +4
  if w >= s { acc = acc + 8 }         ## `>=`                           -> +8

  bare := unchecked (w)               ## `unchecked` around a bare Var, not arithmetic
  if bare > d { acc = acc + 16 }      ## 2^64-6 > 6 unsigned            -> +16

  if unchecked (w + d) < w { acc = acc + 8 }   ## an `unchecked` EXPRESSION operand -> +8

  ## CONTROL — the signed default must survive: two i64s that go negative order SIGNED.
  neg : i64 = 0 - 5
  pos : i64 = 3
  if neg < pos { acc = acc + 3 }      ## -5 < 3 signed                  -> +3
  return acc
}
