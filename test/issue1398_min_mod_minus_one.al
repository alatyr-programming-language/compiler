## Concurrency §6.1: `MIN % -1` yields `0`. The remainder of the minimum value by `-1` is NOT in the
## checked-overflow set — its mathematical result 0 is representable — so a checked `%` answers 0 and does
## not trap, on EVERY backend. The compiler guards the divisor `== -1` case (the same compare as the
## `MIN / -1` guard) and produces 0 WITHOUT EXECUTING the divide, so no target faults on it (CG-8/CG-13):
## x86_64 `idivq` faults on it (`#DE`) and wasm `i64.rem_s` traps on it, while aarch64 `sdiv`+`msub` and
## riscv64 `div`/`rem` define it as 0 in hardware. Before the fix all four trapped: the emitter reused the
## trapping `MIN / -1` guard for `%`, and its own comment already said "`%` (29) never sets `dvmin`:
## `MIN % -1` is 0" — but the native-width arm (`dvmin == 0`) fell through to the INT64_MIN trap anyway.
## Narrow widths were right only by accident: a narrow dividend can never equal the INT64_MIN constant.
##
## Both operands arrive as runtime values (`0 - 1` is a subtraction, not a literal; the minimum is built in
## two steps), so no backend can fold the guard away. Each case contributes a DISTINCT digit, so a wrong
## arm is identifiable from the exit code rather than only from a mismatch:
##   1  `i64` `MIN % -1` through a call — the reported shape
##   2  the same inline in `main`
##   4  `isize` `MIN % -1` through a call (the native signed width spelled its own name)
##   8  NON-VACUITY: `MIN % 1` — an ordinary divide that must still execute (0)
##  16  NON-VACUITY: `MIN % 7` — the remainder of the minimum by an ordinary divisor is `-1`, so a `%`
##      that answered 0 unconditionally would be caught here rather than passing the three arms above
##  32 NON-VACUITY: `100 % -7` — a positive dividend by a negative divisor is `2` (truncating remainder)
## The sum 63 is the pass value; any missing arm subtracts its own digit.
## `MIN / -1` still trapping is the division-overflow member and stays asserted by
## `test/checked_div_min_neg1.al` (`## expect: trap`); it is deliberately NOT repeated here.
divide := fn(a : i64, b : i64) -> i64 { return a % b }
sdivide := fn(a : isize, b : isize) -> isize { return a % b }
main := fn() -> u64 {
  hi : i64 = 0 - 9223372036854775807
  mn := hi - 1
  neg : i64 = 0 - 1
  mut acc : u64 = 0
  if divide(mn, neg) == 0 { acc = acc + 1 }
  if mn % neg == 0 { acc = acc + 2 }
  shi : isize = 0 - 9223372036854775807
  smn := shi - 1
  sneg : isize = 0 - 1
  if sdivide(smn, sneg) == 0 { acc = acc + 4 }
  one : i64 = 1
  if mn % one == 0 { acc = acc + 8 }
  seven : i64 = 7
  if mn % seven == 0 - 1 { acc = acc + 16 }
  neg7 : i64 = 0 - 7
  if 100 % neg7 == 2 { acc = acc + 32 }
  return acc
}
## expect: run 63
