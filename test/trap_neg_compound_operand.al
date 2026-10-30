## #1049 — the wider half of the defect: the grant the parser invented for `-x` was SCOPED, so it
## reached past the negation and into the operand's own subtree. `-(a * b)` lowered the multiply with NO
## overflow guard at all — measured on 0.2.17 at fdc40f6, the emitted body was a bare `imulq` with
## neither `jno` nor `ud2`, while the same `a * b` written plainly emitted both. Every compound operand of
## a negation was silently unchecked: an I11 hole much wider than the `-MIN` case the issue was filed
## for, and invisible to the corpus because no fixture wrote the spelling.
##
## Now the desugar carries no verification-mode grant, so the operand is lowered under the mode the
## SOURCE asked for — checked — and `a * b` keeps its guard whether or not a `-` sits in front of it.
##
## Expected: TRAP (exit 132 on x86_64, `ud2` before the multiply per CG-13; `brk #0` / `ebreak` /
## `unreachable` on the twins). A program that answers a value here is the silent wrong answer I11 forbids.
main := fn() -> i64 {
  mut a : i64 = 4611686018427387904      ## 2^62
  mut b : i64 = 4
  return -(a * b)                         ## 2^64: outside i64 ⇒ the multiply must trap
}
