## #997 — `i8(-129.0)` traps: -129 is one below `i8` MIN.
##
## Concurrency §7.7 (spec v1.6.0): float→int "rounds toward zero … The conversion is checked by
## default: a result outside the integer's range, or a NaN, traps (I11)". Types §4.2, numeric row:
## "toward-zero, range/NaN checked".
##
## Measured on x86_64 at origin/main 55fa477: no trap, exit 7 (the conversion answered 127). The x86 text path emitted a bare `cvttsd2si`
## with no guard.
## Expected: TRAP (exit 132 on x86_64).
main := fn() -> u64 {
  mut f : f64 = 0.0
  f = f - 129.0               ## -129.0
  b := i8(f)                  ## -129 is outside i8 => §7.7 trap
  if b == 127 { return 7 }
  return 9
}
## expect: trap
