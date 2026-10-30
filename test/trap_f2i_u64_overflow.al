## #997 — `u64(1.0e30)` traps: 10^30 is far above 2^64.
##
## Concurrency §7.7 (spec v1.6.0): float→int "rounds toward zero … The conversion is checked by
## default: a result outside the integer's range, or a NaN, traps (I11)". Types §4.2, numeric row:
## "toward-zero, range/NaN checked".
##
## Measured on x86_64 at origin/main 55fa477: no trap, exit 4 (`2^63 >> 61`, the integer-indefinite value). The x86 text path emitted a bare `cvttsd2si`
## with no guard.
## Expected: TRAP (exit 132 on x86_64).
main := fn() -> u64 {
  mut f : f64 = 1.0e15
  f = f * f                   ## 1e30, computed at run time
  x := u64(f)                 ## outside u64 => §7.7 trap
  shr(x, 61)
}
