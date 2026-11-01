## #997 — `u64(-1.0)` traps: -1 is outside `u64`.
##
## Concurrency §7.7 (spec v1.6.0): float→int "rounds toward zero … The conversion is checked by
## default: a result outside the integer's range, or a NaN, traps (I11)". Types §4.2, numeric row:
## "toward-zero, range/NaN checked".
##
## Measured on x86_64 at origin/main 55fa477: no trap, exit 9 (the conversion answered `2^64 - 1`). The x86 text path emitted a bare `cvttsd2si`
## with no guard.
## Expected: TRAP (exit 132 on x86_64).
main := fn() -> u64 {
  mut z : f64 = 0.0
  m := z - 1.0                ## -1.0
  u := u64(m)                 ## -1 is outside u64 => §7.7 trap
  if u == 0 { return 7 }
  return 9
}
## expect: trap
