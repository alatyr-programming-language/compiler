## #1049 / #633 — a WRITTEN signed `0 - v` with `v == MIN` traps, exactly like `-v`.
##
## Concurrency §6.1 (spec v1.6.0): a checked `−` that overflows traps. `0 - MIN` at i64 is 2^63, which
## does not fit. §6.5: the guard is chosen by the operand types and by nothing else, so a literal `0`
## on the left changes nothing about a SIGNED subtraction.
##
## Measured on x86_64 at the parent 2cf60b45: no trap, the program answered `0 - v == v` (exit 0).
## Every emitter skipped the overflow guard whenever the left operand was a zero literal
## (`ex_is_zero_lit`), signed or not. Now the skip is one decision (`ir::zero_left_no_overflow`): only
## an UNSIGNED zero-left subtraction, whose value `2^N - v` the negation rule defines, goes unguarded.
##
## `v` reaches MIN through a call so the operand is not a literal.
## Expected: TRAP (exit 132 on x86_64).
dec := fn(x : i64) -> i64 { x - 1 }
main := fn() -> i64 {
  v : i64 = dec(-9223372036854775807)    ## v == i64 MIN
  w := 0 - v                              ## 2^63 is outside i64 => §6.1 trap
  if w == v { return 0 }
  return 1
}
