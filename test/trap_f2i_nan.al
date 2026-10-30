## #997 — a NaN converted to `i64` traps.
##
## Concurrency §7.7 (spec v1.6.0): float→int "rounds toward zero … The conversion is checked by
## default: a result outside the integer's range, or a NaN, traps (I11)". Types §4.2, numeric row:
## "toward-zero, range/NaN checked".
##
## Measured on x86_64 at origin/main 55fa477: no trap, exit 9 (`cvttsd2si` gave the integer-indefinite value). The x86 text path emitted a bare `cvttsd2si`
## with no guard.
## Expected: TRAP (exit 132 on x86_64).
main := fn() -> u64 {
  mut z : f64 = 0.0
  n := z / z                  ## NaN, computed at run time
  i := i64(n)                 ## NaN => §7.7 trap
  if i == 0 { return 7 }
  return 9
}
