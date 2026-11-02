## #1374 — inside `unchecked`, a NaN or out-of-range float→int conversion gives a value, never a
## trap.
##
## Concurrency §7.7 (spec v1.6.0): "Inside an `unchecked` scope the conversion is hardware-defined
## (§6.2; the out-of-range result depends on the ISA)". The value is the ISA's, so this fixture
## does not assert it; it asserts only that each conversion answers one (no backend's hardware
## answers 1 to all four). The checked guard (#997, #1374) must not leak into the unchecked form.
##
## Measured on #1222's head c4058737: x86_64, aarch64 and riscv64 exit 42; wasm traps (134), because
## its `i64.trunc_f64_*` traps on a NaN or an out-of-range operand. wasm now uses the non-trapping
## `i64.trunc_sat_f64_*`, the ISA's own unchecked conversion.
## Expected: exit 42 on every backend.
main := fn() -> u64 {
  mut z : f64 = 0.0
  mut big : f64 = 1.0e30
  a := unchecked u8(z / z)
  b := unchecked i64(big)
  c := unchecked u64(0.0 - big)
  d := unchecked u32(big)
  if a == 1 and b == 1 and c == 1 and d == 1 { return 1 }
  return 42
}
## expect: run 42
