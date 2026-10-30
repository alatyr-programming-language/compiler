## #997 — `u8(300.0)` traps instead of answering 300 mod 256.
##
## Concurrency §7.7 (spec v1.6.0): float→int "rounds toward zero … The conversion is checked by
## default: a result outside the integer's range, or a NaN, traps (I11)". Types §4.2, numeric row:
## "toward-zero, range/NaN checked".
##
## Measured on x86_64 at origin/main 55fa477: no trap, exit 7 (the conversion answered 44). The x86 text path emitted a bare `cvttsd2si`
## with no guard.
## Expected: TRAP (exit 132 on x86_64).
main := fn() -> u64 {
  mut f : f64 = 150.0
  f = f * 2.0                 ## 300.0
  b := u8(f)                  ## 300 is outside u8 => §7.7 trap
  if b == 44 { return 7 }
  return 42
}
