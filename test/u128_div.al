## e2e — ROADMAP §8.4 part 3, TYP-10 slice C: DIVIDE (`/`) and REMAINDER (`%`) on the prelude
## `u128 ≡ uint(128)` (Types §3/§7, TYP-2 / TYP-10 / D23 / D24; operators.md OP-1). Binary LONG
## DIVISION (shift-subtract), COMPTIME-UNROLLED over the N bits inside the `@inline` generic
## operator bodies themselves (lib/base/u128.al): an `@inline` operator body cannot hold a runtime
## `while` (the inline expander has no loop form) and a comptime-param helper fn is not declarable,
## so the loop is `comptime for i in 0 .. N` with the conditional subtract expressed branch-free
## (the borrow ripple's final carry becomes an all-ones mask; the quotient bit is that carry
## shifted to the step's position). Division by zero is a checked trap. Operands are LOCALS (a
## StructLit operand can't be type-inferred by the route yet — same front-end gap noted for `*`).
##
## Cases cross the word boundary in both the dividend and the quotient:
##   [0, 6] / [2, 0]    = [0, 3]   — 6·2^64 / 2 = 3·2^64, quotient in the HIGH word
##   [54, 0] / [9, 0]   = [6, 0]   — plain low divide
##   [1000, 0]/[30, 0]  = [33, 0]  — low divide with a remainder (1000 = 33·30 + 10)
##   [54, 0] % [9, 0]   = [0, 0]   — exact remainder (54 = 6·9): MUST be 0
## 42 = q1.w1 + q2.w0 + q3.w0 + rem.w0 = 3 + 6 + 33 + 0. A high-word divide bug misses q1.w1=3;
## a broken `%` makes rem.w0 != 0 and overshoots 42.
main := fn() -> u64 {
  a := u128(words = [0, 6])
  b := u128(words = [2, 0])
  q1 := a / b

  c := u128(words = [54, 0])
  e := u128(words = [9, 0])
  q2 := c / e

  f := u128(words = [1000, 0])
  g := u128(words = [30, 0])
  q3 := f / g

  rem := c % e

  return q1.words[1] + q2.words[0] + q3.words[0] + rem.words[0]
}
