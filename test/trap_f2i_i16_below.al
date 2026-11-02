## #1374 — `i16(-32769.0)` traps: -32769 is one below `i16` MIN.
##
## Concurrency §7.7 (spec v1.6.0): float→int "rounds toward zero … The conversion is checked by
## default: a result outside the integer's range, or a NaN, traps (I11)". Types §4.2, numeric row:
## "toward-zero, range/NaN checked".
##
## Measured on #1222's head c4058737 (x86_64 already guarded): x86_64 traps (132); aarch64, riscv64
## and wasm exit 9 (the low 16 bits, 32767). The twins' conversion had no guard: aarch64 `fcvtz*`
## and riscv64 `fcvt.*` saturate, and wasm's 64-bit truncation accepts any value that fits 64 bits.
## Expected: TRAP on every backend.
main := fn() -> u64 {
  mut one : f64 = 1.0
  v := i16(0.0 - 32769.0 * one)   ## outside i16 => §7.7 trap
  if v == 0 { return 7 }
  return 9
}
## expect: trap
