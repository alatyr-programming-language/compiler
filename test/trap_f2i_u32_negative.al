## #1374 — `u32(-1.0)` traps: -1 is outside `u32`.
##
## Concurrency §7.7 (spec v1.6.0): float→int "rounds toward zero … The conversion is checked by
## default: a result outside the integer's range, or a NaN, traps (I11)". Types §4.2, numeric row:
## "toward-zero, range/NaN checked".
##
## Measured on #1222's head c4058737 (x86_64 already guarded): x86_64 traps (132); aarch64 and
## riscv64 exit 7 (saturated to 0), wasm traps only because its 64-bit truncation does. The twins'
## conversion had no guard: aarch64 `fcvtz*` and riscv64 `fcvt.*` saturate, and wasm's 64-bit
## truncation accepts any value that fits 64 bits.
## Expected: TRAP on every backend.
main := fn() -> u64 {
  mut one : f64 = 1.0
  v := u32(0.0 - one)             ## outside u32 => §7.7 trap
  if v == 0 { return 7 }
  return 9
}
## expect: trap
