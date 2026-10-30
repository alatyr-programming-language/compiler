## #997 — `i64(2^63)` traps: 2^63 is one above `i64` MAX.
##
## Concurrency §7.7 (spec v1.6.0): float→int "rounds toward zero … The conversion is checked by
## default: a result outside the integer's range, or a NaN, traps (I11)". Types §4.2, numeric row:
## "toward-zero, range/NaN checked".
##
## Measured on x86_64 at origin/main 55fa477: no trap, exit 7 (the conversion answered i64 MIN). The x86 text path emitted a bare `cvttsd2si`
## with no guard.
## Expected: TRAP (exit 132 on x86_64).
main := fn() -> u64 {
  mut t : f64 = 4294967296.0
  t = t * t * 0.5             ## 2^63, exact in f64
  i := i64(t)                 ## 2^63 is outside i64 => §7.7 trap
  if i < 0 { return 7 }
  return 9
}
