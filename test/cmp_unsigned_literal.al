## e2e (Types §9.1 / §11): an ORDERING comparison between an UNSIGNED value and an integer LITERAL
## must be UNSIGNED. It was SIGNED — an integer literal carries no type span, so the "both operands
## provably unsigned" guard could never prove the literal side, and every `uN`/`usize` compared
## against a literal fell back to the signed setcc. Below 2^63 the two agree, which is why this hid;
## at or above 2^63 the unsigned value reads as negative and EVERY ordering flips. Probed on the
## pre-fix compiler: with `n : u64 = 2**63`, `n >= 10` was FALSE, `n > 1` was FALSE, `n < 100` was
## TRUE. The same comparisons against a u64 VARIABLE holding 10/1/100 were already correct.
##
## This is the ROOT of the `int_literal_2p63` fixture's bug: the compiler's own decimal renderer
## `rt::sb_uint` guarded its recursion with `n >= 10` on a `usize`, which compiled signed, so at 2^63
## the guard read negative, one digit was emitted and `2**63` printed as `-8`. That site was rewritten
## as the signedness-independent `n / 10 != 0`; this fixture locks the actual rule.
##
## Covered here: both operand ORDERS (`n >= 10` and `10 <= n`), all four orderings, `u64`/`usize`,
## a literal AT or ABOVE 2^63 (which as an `i64` word is negative — `5 < 2**63` compared as `5 < -8`
## → FALSE, and `5 < u64::MAX` as `5 < -1` → FALSE), and the SIGNED controls that must NOT flip:
## an `i64` against a literal (`x < 1` TRUE, `x > 1` FALSE) and against a written NEGATIVE literal
## (`x < -1` is TRUE for x = -5 under the SIGNED reading and FALSE under an unsigned one — unary
## minus parses as a `Bin`, never a literal, so it can never pull the pair to unsigned).
## `==`/`!=` are signedness-free and are included as invariants.
##
## Cross-backend: aarch64 / riscv64 / wat carry the same guard and had the identical hole. The result
## is kept under 126 so the WASI `proc_exit` bound is respected.
main := fn() -> u64 {
  n : u64 = 9223372036854775808
  s : usize = 9223372036854775808
  m : u64 = 5
  x : i64 = 0 - 5
  mut good : u64 = 0
  mut bad : u64 = 0

  ## --- u64 at 2^63, VARIABLE on the left, small literal on the right (must be TRUE/FALSE as written)
  if n >= 10 { good = good + 1 }
  if n > 1 { good = good + 1 }
  if n < 100 { bad = bad + 1 }
  if n <= 100 { bad = bad + 1 }

  ## --- the same, LITERAL on the left
  if 10 <= n { good = good + 1 }
  if 1 < n { good = good + 1 }
  if 100 > n { bad = bad + 1 }
  if 100 >= n { bad = bad + 1 }

  ## --- a literal that does NOT fit in an i64 (its i64 word is negative), both orders
  if m < 9223372036854775808 { good = good + 1 }
  if 9223372036854775808 > m { good = good + 1 }
  if m >= 9223372036854775808 { bad = bad + 1 }
  if m < 18446744073709551615 { good = good + 1 }

  ## --- usize behaves like u64
  if s >= 10 { good = good + 1 }
  if s > 1 { good = good + 1 }
  if s < 100 { bad = bad + 1 }
  if 1 < s { good = good + 1 }

  ## --- CONTROLS: a SIGNED operand must keep the SIGNED comparison
  if x < 1 { good = good + 1 }
  if x < -1 { good = good + 1 }
  if x > 1 { bad = bad + 1 }
  if 1 > x { good = good + 1 }

  ## --- CONTROLS: equality is signedness-free
  if n == 10 { bad = bad + 1 }
  if n != 10 { good = good + 1 }

  ## 14 TRUE checks, 8 FALSE checks — success is exactly `good == 14 and bad == 0`, reported as 42.
  ## Any other outcome reports the pair as `good * 8 + bad`, which names the failure while staying
  ## under 126 (the WASI `proc_exit` bound the cross-arch sweeps run under): at most 13*8 + 8 = 112.
  if good == 14 { if bad == 0 { return 42 } }
  if good > 13 { good = 13 }
  return good * 8 + bad
}
